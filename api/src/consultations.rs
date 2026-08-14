//! Handlers `/v1/cabinet/consultations/:id` — complétion, note, liste d'une
//! séance. Le contexte (`GET /v1/cabinet/consultations/:id`) vit dans
//! `consultation_context.rs` (extrait, refactor taille CLAUDE.md).

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    consultation_context::{ConsultationActItem, PractitionerSummary},
    notify,
    patient_guardianship::aggregate_guardianship,
    AppState,
};

// ── POST /v1/cabinet/consultations/:id/complete ───────────────────────────────

/// Réponse de `POST /v1/cabinet/consultations/:id/complete`.
#[derive(Serialize)]
pub struct CompleteConsultationResponse {
    /// Id de la facture/devis créé (statut `sent`, #4260), si des actes CCAM
    /// étaient présents.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub invoice_id: Option<Uuid>,
    /// Prochaine étape suggérée (ex. "sign_quote", "no_action").
    pub next_step: String,
    /// Séances restantes (`planned_sessions - completed_sessions`) sur la
    /// phase de traitement décomptée par cette clôture (#4120). `null` si
    /// aucun acte de cette séance n'était rattaché à une phase à séances
    /// programmées, ou si plusieurs phases distinctes l'étaient (ambigu —
    /// toutes sont décomptées, mais un seul champ ne peut représenter les
    /// deux restants à la fois).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub sessions_remaining: Option<i32>,
}

/// `POST /v1/cabinet/consultations/:id/complete` — clôture la séance et génère le devis.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// - Passe `consultation_session.status` en `completed` et pose `completed_at`.
/// - Passe `appointment.status` en `done` et pose `appointment.completed_at`.
/// - Crée une notification `review_request` pour le patient (RDV honoré,
///   #4152) — silencieuse si le patient n'a pas de compte app.
/// - Si des actes CCAM existent pour ce RDV, crée un `quote` en `sent`
///   (#4260 — visible immédiatement côté patient, RLS `quote_patient_read`
///   exige status <> 'draft') avec les `quote_item` correspondants (chacun
///   hérite du `phase_id` de son acte d'origine) et retourne `invoice_id`.
/// - #4120 : pour chaque `treatment_phase` distincte rattachée à au moins
///   un acte de cette séance (`consultation_act.phase_id`, migration 0203)
///   et utilisant le mécanisme de séances programmées (`planned_sessions`
///   non NULL), incrémente `completed_sessions` (capé, jamais au-delà de
///   `planned_sessions`). `sessions_remaining` dans la réponse si une seule
///   phase était concernée (sinon `null`, ambigu entre plusieurs phases).
/// - Séance déjà `completed` ou `cancelled` → `409 invalid_status`.
/// - Séance inexistante ou hors tenant → `404`.
pub async fn complete_consultation(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<CompleteConsultationResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Récupère la séance + appointment_id + practitioner_id, vérifie tenant et statut.
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status \
         FROM consultation_session cs \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien propriétaire de la séance peut la clôturer.
    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    if session_status != "in_progress" {
        return Err(AppError::InvalidStatus);
    }

    // Clôture la séance.
    sqlx::query(
        "UPDATE consultation_session \
         SET status = 'completed', completed_at = now(), updated_at = now() \
         WHERE id = $1",
    )
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Clôture le RDV associé.
    sqlx::query(
        "UPDATE appointment \
         SET status = 'done', completed_at = now(), updated_at = now() \
         WHERE id = $1",
    )
    .bind(appointment_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Demande d'avis (#4152) : RDV honoré → notification in-app au patient,
    // deeplink vers POST /v1/reviews. Via app_user_id direct sinon via le
    // compte patient rattaché — même pattern que
    // scheduling.rs::call_next_patient. Patient sans compte (ni app_user_id
    // ni patient_account_id) → silencieusement aucune notification, pas une
    // erreur (cas normal d'un patient walk-in).
    let patient_row = sqlx::query(
        "SELECT p.app_user_id, p.patient_account_id \
         FROM appointment a \
         JOIN patient p ON p.id = a.patient_id \
         WHERE a.id = $1",
    )
    .bind(appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if let Some(row) = patient_row {
        let patient_app_user_id: Option<Uuid> =
            row.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        let patient_account_id: Option<Uuid> = row
            .try_get("patient_account_id")
            .map_err(|_| AppError::Internal)?;
        let title = "Comment s'est passé votre rendez-vous ?";
        let data = serde_json::json!({ "appointment_id": appointment_id });
        if let Some(uid) = patient_app_user_id {
            notify::notify_user(&mut tx, uid, "review_request", title, data).await?;
        } else if let Some(account_id) = patient_account_id {
            notify::notify_patient_account(&mut tx, account_id, "review_request", title, data)
                .await?;
        }
    }

    // Récupère les actes CCAM pour ce RDV.
    let act_rows = sqlx::query(
        "SELECT id, patient_id, label, ccam_code, tooth, amount_cents, phase_id \
         FROM consultation_act \
         WHERE appointment_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at ASC",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let invoice_id = if act_rows.is_empty() {
        None
    } else {
        // Déduit le patient_id depuis le premier acte (tous partagent le même).
        let patient_id: Uuid = act_rows[0]
            .try_get("patient_id")
            .map_err(|_| AppError::Internal)?;

        // Calcule le total en centimes pour le devis.
        let mut total_cents: i64 = 0;
        for row in &act_rows {
            let cents: i32 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            total_cents += i64::from(cents);
        }

        // Responsable légal (#4098, même résolution que
        // cabinet_quotes.rs::create_cabinet_quote) : si le bénéficiaire des
        // soins a un compte plateforme lié et qu'un tuteur actif lui est
        // rattaché, le devis lui est aussi facturable — sans quoi
        // quote_patient_read (migration 0175) ne l'expose jamais au tuteur
        // d'un dépendant (issue #4591).
        let patient_account_id: Option<Uuid> =
            sqlx::query("SELECT patient_account_id FROM patient WHERE id = $1 AND cabinet_id = $2")
                .bind(patient_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .and_then(|row| row.try_get("patient_account_id").ok());
        let billed_to_account_id = match patient_account_id {
            Some(account_id) => {
                let (guardians, _dependents) = aggregate_guardianship(&mut tx, account_id).await?;
                guardians.into_iter().next().map(|g| g.account_id)
            }
            None => None,
        };

        // Crée le devis déjà envoyé (#4260) : la policy RLS quote_patient_read
        // (migrations 0134/0175) exige status <> 'draft' pour qu'un patient
        // puisse lire son devis — un devis créé en 'draft' à la clôture de
        // consultation restait donc invisible côté patient tant qu'aucun
        // POST .../quotes/:id/send explicite n'était appelé (aucune séance de
        // ce flux n'en déclenche un). Aucun autre effet de bord à 'sent'
        // (cf. cabinet_quotes.rs::send_cabinet_quote — simple UPDATE status,
        // pas de génération PDF/notification ici).
        let quote_row = sqlx::query(
            // #4126 : sent_at posé dès la création (déjà 'sent'), départ du
            // calendrier de relance J+3/J+7.
            "INSERT INTO quote \
             (cabinet_id, patient_id, status, total_amount, currency, sent_at, \
              billed_to_account_id) \
             VALUES ($1, $2, 'sent', $3::numeric / 100, 'EUR', now(), $4) \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(patient_id)
        .bind(total_cents)
        .bind(billed_to_account_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let quote_id: Uuid = quote_row.try_get("id").map_err(|_| AppError::Internal)?;

        // Tarifs de référence des codes CCAM présents (#4062) : une seule
        // requête plutôt qu'un lookup par ligne. ccam_act est non-tenant
        // (migration 0119), pas de scope RLS requis ici.
        let ccam_codes: Vec<String> = act_rows
            .iter()
            .filter_map(|row| row.try_get::<Option<String>, _>("ccam_code").ok().flatten())
            .collect();
        let tarif_rows = if ccam_codes.is_empty() {
            Vec::new()
        } else {
            sqlx::query("SELECT code, tarif_cents FROM ccam_act WHERE code = ANY($1)")
                .bind(&ccam_codes)
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
        };
        let tarifs: std::collections::HashMap<String, i32> = tarif_rows
            .iter()
            .filter_map(|row| {
                let code: String = row.try_get("code").ok()?;
                let tarif: Option<i32> = row.try_get("tarif_cents").ok()?;
                tarif.map(|t| (code, t))
            })
            .collect();

        // Crée les lignes du devis.
        for row in &act_rows {
            let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
            let ccam_code: Option<String> =
                row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
            let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
            let amount_cents: i32 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;
            let phase_id: Option<Uuid> = row.try_get("phase_id").map_err(|_| AppError::Internal)?;

            // Part AMO estimée (#4062) : taux dentaire standard appliqué au
            // tarif de référence CCAM (base de remboursement indicative,
            // PAS le montant facturé) — première approximation explicitement
            // demandée par l'issue, en l'absence de grille de remboursement
            // réelle par acte. `None` (jamais 0) si le code est absent ou non
            // référencé dans le catalogue : ne pas fabriquer un reste à
            // charge sur une donnée qu'on n'a pas (même principe que
            // panier_sante, #4055). Plafonné à amount_cents : l'AMO ne peut
            // pas rembourser plus que le montant réellement facturé.
            const AMO_RATE_DENTAIRE: f64 = 0.70;
            let amo_part_cents: Option<i64> = ccam_code
                .as_deref()
                .and_then(|code| tarifs.get(code))
                .map(|&tarif_cents| {
                    let estimated = (f64::from(tarif_cents) * AMO_RATE_DENTAIRE).round() as i64;
                    estimated.min(i64::from(amount_cents))
                });

            sqlx::query(
                "INSERT INTO quote_item \
                 (cabinet_id, quote_id, label, ccam_code, tooth, qty, unit_amount, amo_part, phase_id) \
                 VALUES ($1, $2, $3, $4, $5, 1, $6::numeric / 100, $7::numeric / 100, $8)",
            )
            .bind(claims.cabinet_id)
            .bind(quote_id)
            .bind(&label)
            .bind(&ccam_code)
            .bind(&tooth)
            .bind(i64::from(amount_cents))
            .bind(amo_part_cents)
            .bind(phase_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }

        Some(quote_id)
    };

    // #4120 : décompte des séances programmées — pour chaque phase distincte
    // rattachée à au moins un acte de CETTE séance (phase_id sur
    // consultation_act, migration 0203), incrémente completed_sessions.
    // Capé à planned_sessions (LEAST) plutôt qu'un simple +1 : une même
    // phase peut être touchée par plusieurs actes de la séance, mais une
    // séance ne compte qu'une fois, et jamais au-delà de la contrainte
    // CHECK treatment_phase_completed_not_over_planned. Les phases sans
    // planned_sessions (mécanisme non utilisé) ne matchent simplement pas
    // la clause WHERE — no-op silencieux, comportement historique préservé.
    let mut touched_phase_ids: Vec<Uuid> = act_rows
        .iter()
        .filter_map(|row| row.try_get::<Option<Uuid>, _>("phase_id").ok().flatten())
        .collect();
    touched_phase_ids.sort();
    touched_phase_ids.dedup();

    let mut sessions_remaining: Option<i32> = None;
    for phase_id in &touched_phase_ids {
        let phase_row = sqlx::query(
            "UPDATE treatment_phase \
             SET completed_sessions = LEAST(completed_sessions + 1, planned_sessions) \
             WHERE id = $1 AND cabinet_id = $2 AND planned_sessions IS NOT NULL \
             RETURNING completed_sessions, planned_sessions",
        )
        .bind(phase_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        if let Some(row) = phase_row {
            let completed: i32 = row
                .try_get("completed_sessions")
                .map_err(|_| AppError::Internal)?;
            let planned: i32 = row
                .try_get("planned_sessions")
                .map_err(|_| AppError::Internal)?;
            // Une seule phase décomptée dans cette séance -> champ non
            // ambigu, sinon (rare, plusieurs phases sur la même séance)
            // toutes sont décomptées mais aucune n'est reportée seule.
            sessions_remaining = if touched_phase_ids.len() == 1 {
                Some(planned - completed)
            } else {
                None
            };
        }
    }

    // Audit.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'practitioner', 'complete_consultation', 'consultation_session', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let next_step = if invoice_id.is_some() {
        "sign_quote"
    } else {
        "no_action"
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        appointment_id = %appointment_id,
        invoice_id = ?invoice_id,
        "consultation completed"
    );

    Ok(Json(CompleteConsultationResponse {
        invoice_id,
        next_step: next_step.to_string(),
        sessions_remaining,
    }))
}

// ── PUT /v1/cabinet/consultations/:id/note ────────────────────────────────────

/// Body de `PUT /v1/cabinet/consultations/:id/note`.
#[derive(Deserialize)]
pub struct SetConsultationNoteBody {
    pub note: String,
}

/// Réponse de `PUT /v1/cabinet/consultations/:id/note`.
#[derive(Serialize)]
pub struct SetConsultationNoteResponse {
    pub note: String,
}

/// `PUT /v1/cabinet/consultations/:id/note` — enregistre la note de séance (chiffrée).
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Seul le praticien propriétaire de la séance peut écrire sa note.
/// Séance `cancelled` ou `completed` → `409 invalid_status` (séance figée, non
/// éditable — même gel que les actes, cf. `add_consultation_act`).
/// Chiffrement colonne : stub `"STUB_ENC:" + XOR 0xFF` en dev — AES-256-GCM/KMS
/// à NUB-T3 (ADR-009), voir `clinical.rs::add_patient_note`.
/// Séance inexistante ou hors tenant → 404.
/// Écriture auditée dans `audit_log` (action `set_consultation_note`).
pub async fn set_consultation_note(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<SetConsultationNoteBody>,
) -> Result<Json<SetConsultationNoteResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let session_row = sqlx::query(
        "SELECT cs.practitioner_id, cs.status \
         FROM consultation_session cs \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien propriétaire de la séance peut écrire sa note.
    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    if status == "cancelled" || status == "completed" {
        return Err(AppError::InvalidStatus);
    }

    // Stub chiffrement : préfixe "STUB_ENC:" + XOR 0xFF octet à octet.
    // Remplacé par AES-256-GCM + KMS Scaleway à NUB-T3 (ADR-009).
    let mut ciphertext: Vec<u8> = b"STUB_ENC:".to_vec();
    ciphertext.extend(body.note.as_bytes().iter().map(|b| b ^ 0xFF));

    sqlx::query(
        "UPDATE consultation_session \
         SET note_ciphertext = $1, note_key_ref = 'stub-key-ref', updated_at = now() \
         WHERE id = $2",
    )
    .bind(&ciphertext)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Audit.
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, 'practitioner', 'set_consultation_note', 'consultation_session', $3)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        "consultation note saved"
    );

    Ok(Json(SetConsultationNoteResponse { note: body.note }))
}

// ── /v1/cabinet/consultations/:id/acts (CRUD) — voir consultation_acts.rs ────

// ── GET /v1/cabinet/consultations ────────────────────────────────────────────

/// Un élément de `GET /v1/cabinet/consultations` (historique des séances).
/// Volontairement sans note clinique : la liste sert l'historique (praticien),
/// le détail chiffré passe par `GET /v1/cabinet/consultations/:id`.
/// `acts` ne contient que le premier acte (créé en premier) de la séance —
/// utilisé par l'encart « Dernières séances » (#4937), pas la liste complète.
#[derive(Serialize)]
pub struct ConsultationListItem {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub patient_id: Uuid,
    pub patient_name: String,
    pub practitioner: PractitionerSummary,
    pub status: String,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    pub acts_count: i64,
    pub acts: Vec<ConsultationActItem>,
}

/// Réponse de `GET /v1/cabinet/consultations`.
#[derive(Serialize)]
pub struct ConsultationListResponse {
    pub data: Vec<ConsultationListItem>,
}

/// Query de `GET /v1/cabinet/consultations`.
#[derive(Deserialize)]
pub struct ListConsultationsQuery {
    pub patient_id: Option<Uuid>,
    pub status: Option<String>,
    pub limit: Option<i64>,
}

/// `GET /v1/cabinet/consultations` — historique des séances du cabinet (#3232).
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Filtres : `patient_id`, `status` (in_progress|completed|cancelled).
/// Tri `started_at` DESC, `limit` 1..=100 (défaut 50).
/// `status` inconnu → 422.
pub async fn list_consultations(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Query(query): Query<ListConsultationsQuery>,
) -> Result<Json<ConsultationListResponse>, AppError> {
    if let Some(s) = query.status.as_deref() {
        if !matches!(s, "in_progress" | "completed" | "cancelled") {
            return Err(AppError::ValidationError);
        }
    }
    let limit = query.limit.unwrap_or(50).clamp(1, 100);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, \
                a.patient_id, \
                COALESCE(pat.first_name || ' ' || pat.last_name, '') AS patient_name, \
                COALESCE(prov.display_name, '') AS practitioner_name, \
                (SELECT count(*) FROM consultation_act ca \
                  WHERE ca.appointment_id = cs.appointment_id \
                    AND ca.cabinet_id = cs.cabinet_id) AS acts_count, \
                fa.id AS first_act_id, fa.ccam_code AS first_act_ccam_code, \
                fa.label AS first_act_label, fa.tooth AS first_act_tooth, \
                fa.amount_cents AS first_act_amount_cents \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         LEFT JOIN patient pat ON pat.id = a.patient_id \
                               AND pat.cabinet_id = cs.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = cs.practitioner_id \
                                 AND prov.cabinet_id = cs.cabinet_id \
         LEFT JOIN LATERAL ( \
             SELECT ca.id, ca.ccam_code, ca.label, ca.tooth, ca.amount_cents \
             FROM consultation_act ca \
             WHERE ca.appointment_id = cs.appointment_id \
               AND ca.cabinet_id = cs.cabinet_id \
             ORDER BY ca.created_at ASC \
             LIMIT 1 \
         ) fa ON true \
         WHERE cs.cabinet_id = $1 \
           AND ($2::uuid IS NULL OR a.patient_id = $2) \
           AND ($3::text IS NULL OR cs.status = $3) \
         ORDER BY cs.started_at DESC \
         LIMIT $4",
    )
    .bind(claims.cabinet_id)
    .bind(query.patient_id)
    .bind(query.status.as_deref())
    .bind(limit)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            let started_at: chrono::DateTime<chrono::Utc> =
                r.try_get("started_at").map_err(|_| AppError::Internal)?;
            let completed_at: Option<chrono::DateTime<chrono::Utc>> =
                r.try_get("completed_at").map_err(|_| AppError::Internal)?;
            // Premier acte (créé en premier) de la séance, s'il existe — voir
            // le LATERAL join `fa` ci-dessus (#4937, encart « Dernières séances »).
            let first_act_id: Option<Uuid> =
                r.try_get("first_act_id").map_err(|_| AppError::Internal)?;
            let first_act_ccam_code: Option<String> = r
                .try_get("first_act_ccam_code")
                .map_err(|_| AppError::Internal)?;
            let first_act_label: Option<String> = r
                .try_get("first_act_label")
                .map_err(|_| AppError::Internal)?;
            let first_act_tooth: Option<String> = r
                .try_get("first_act_tooth")
                .map_err(|_| AppError::Internal)?;
            let first_act_amount_cents: Option<i32> = r
                .try_get("first_act_amount_cents")
                .map_err(|_| AppError::Internal)?;
            let acts = match (first_act_id, first_act_ccam_code, first_act_label) {
                (Some(id), Some(ccam_code), Some(label)) => vec![ConsultationActItem {
                    id,
                    ccam_code,
                    label,
                    tooth: first_act_tooth,
                    amount_cents: first_act_amount_cents.unwrap_or(0),
                }],
                _ => vec![],
            };
            Ok(ConsultationListItem {
                id: r.try_get("id").map_err(|_| AppError::Internal)?,
                appointment_id: r
                    .try_get("appointment_id")
                    .map_err(|_| AppError::Internal)?,
                patient_id: r.try_get("patient_id").map_err(|_| AppError::Internal)?,
                patient_name: r.try_get("patient_name").map_err(|_| AppError::Internal)?,
                practitioner: PractitionerSummary {
                    id: r
                        .try_get("practitioner_id")
                        .map_err(|_| AppError::Internal)?,
                    display_name: r
                        .try_get("practitioner_name")
                        .map_err(|_| AppError::Internal)?,
                },
                status: r.try_get("status").map_err(|_| AppError::Internal)?,
                started_at: started_at.to_rfc3339(),
                completed_at: completed_at.map(|t| t.to_rfc3339()),
                acts_count: r.try_get("acts_count").map_err(|_| AppError::Internal)?,
                acts,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ConsultationListResponse { data }))
}
