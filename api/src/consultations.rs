//! Handlers `/v1/cabinet/consultations/:id` — contexte et complétion d'une séance.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un acte CCAM réalisé pendant la séance.
#[derive(Serialize)]
pub struct ConsultationActItem {
    pub id: Uuid,
    pub ccam_code: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth: Option<String>,
    pub amount_cents: i32,
}

/// Sous-objet praticien dans la réponse.
#[derive(Serialize)]
pub struct PractitionerSummary {
    pub id: Uuid,
    pub display_name: String,
}

/// Réponse de `GET /v1/cabinet/consultations/:id`.
#[derive(Serialize)]
pub struct ConsultationContextResponse {
    pub id: Uuid,
    pub appointment_id: Uuid,
    pub status: String,
    pub started_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub completed_at: Option<String>,
    pub practitioner: PractitionerSummary,
    /// Note clinique déchiffrée. `None` si aucune note enregistrée.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    pub acts: Vec<ConsultationActItem>,
}

/// `GET /v1/cabinet/consultations/:id` — contexte clinique d'une séance au fauteuil.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Garde relation-de-soin E.2.16.c §14 (miroir `medical_record.rs`) : le praticien
/// appelant doit avoir eu au moins un `appointment` avec le patient de la séance,
/// sinon 403 — même s'il est dans le même cabinet.
/// Note clinique : déchiffrée via stub `STUB_ENC:` (AES-256-GCM/KMS à NUB-T3, ADR-009).
/// Séance inexistante ou hors tenant → 404.
pub async fn get_consultation_context(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationContextResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Séance + display_name du praticien via provider (peut être NULL si provider absent).
    let session_row = sqlx::query(
        "SELECT cs.id, cs.appointment_id, cs.practitioner_id, cs.status, \
                cs.started_at, cs.completed_at, cs.note_ciphertext, cs.note_key_ref, \
                COALESCE(p.display_name, '') AS display_name \
         FROM consultation_session cs \
         LEFT JOIN provider p ON p.practitioner_id = cs.practitioner_id \
                              AND p.cabinet_id = cs.cabinet_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let session_id: Uuid = session_row.try_get("id").map_err(|_| AppError::Internal)?;
    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // RLS strict E.2.16.c : le praticien appelant doit avoir eu au moins un
    // appointment avec le patient de cette séance (§14 — miroir de medical_record.rs).
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = (SELECT patient_id FROM appointment WHERE id = $1 AND cabinet_id = $2) \
           AND a.cabinet_id = $2 AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let started_at: chrono::DateTime<chrono::Utc> = session_row
        .try_get("started_at")
        .map_err(|_| AppError::Internal)?;
    let completed_at: Option<chrono::DateTime<chrono::Utc>> = session_row
        .try_get("completed_at")
        .map_err(|_| AppError::Internal)?;
    let note_ciphertext: Option<Vec<u8>> = session_row
        .try_get("note_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let display_name: String = session_row
        .try_get("display_name")
        .map_err(|_| AppError::Internal)?;

    // Déchiffre `note_ciphertext` via stub (KMS/AES-256-GCM à NUB-T3, ADR-009) —
    // voir `clinical.rs::add_patient_note` pour le même stub sur `clinical_note`.
    let note: Option<String> = note_ciphertext.as_deref().and_then(stub_decrypt_note);

    // Actes CCAM de la séance.
    let act_rows = sqlx::query(
        "SELECT id, ccam_code, label, tooth, amount_cents \
         FROM consultation_act \
         WHERE appointment_id = $1 AND cabinet_id = $2 \
         ORDER BY created_at ASC",
    )
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut acts: Vec<ConsultationActItem> = Vec::with_capacity(act_rows.len());
    for row in act_rows {
        let act_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let ccam_code: String = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let amount_cents: i32 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        acts.push(ConsultationActItem {
            id: act_id,
            ccam_code,
            label,
            tooth,
            amount_cents,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %session_id,
        "consultation context queried"
    );

    Ok(Json(ConsultationContextResponse {
        id: session_id,
        appointment_id,
        status,
        started_at: started_at.to_rfc3339(),
        completed_at: completed_at.map(|t| t.to_rfc3339()),
        practitioner: PractitionerSummary {
            id: practitioner_id,
            display_name,
        },
        note,
        acts,
    }))
}

// ── POST /v1/cabinet/consultations/:id/complete ───────────────────────────────

/// Réponse de `POST /v1/cabinet/consultations/:id/complete`.
#[derive(Serialize)]
pub struct CompleteConsultationResponse {
    /// Id de la facture/devis créé en draft, si des actes CCAM étaient présents.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub invoice_id: Option<Uuid>,
    /// Prochaine étape suggérée (ex. "sign_quote", "no_action").
    pub next_step: String,
}

/// `POST /v1/cabinet/consultations/:id/complete` — clôture la séance et génère le devis.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// - Passe `consultation_session.status` en `completed` et pose `completed_at`.
/// - Passe `appointment.status` en `done` et pose `appointment.completed_at`.
/// - Si des actes CCAM existent pour ce RDV, crée un `quote` en `draft`
///   avec les `quote_item` correspondants et retourne `invoice_id`.
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

    // Récupère les actes CCAM pour ce RDV.
    let act_rows = sqlx::query(
        "SELECT id, patient_id, label, ccam_code, tooth, amount_cents \
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

        // Crée le devis en draft.
        let quote_row = sqlx::query(
            "INSERT INTO quote \
             (cabinet_id, patient_id, status, total_amount, currency) \
             VALUES ($1, $2, 'draft', $3::numeric / 100, 'EUR') \
             RETURNING id",
        )
        .bind(claims.cabinet_id)
        .bind(patient_id)
        .bind(total_cents)
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
                 (cabinet_id, quote_id, label, ccam_code, tooth, qty, unit_amount, amo_part) \
                 VALUES ($1, $2, $3, $4, $5, 1, $6::numeric / 100, $7::numeric / 100)",
            )
            .bind(claims.cabinet_id)
            .bind(quote_id)
            .bind(&label)
            .bind(&ccam_code)
            .bind(&tooth)
            .bind(i64::from(amount_cents))
            .bind(amo_part_cents)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }

        Some(quote_id)
    };

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
    }))
}

// ── PUT /v1/cabinet/consultations/:id/note ────────────────────────────────────

/// Inverse du stub chiffrement `note_ciphertext` : supprime le préfixe `STUB_ENC:`
/// et XOR 0xFF octet à octet. Même stub que `clinical.rs::add_patient_note`
/// (KMS/AES-256-GCM à NUB-T3, ADR-009). `None` si préfixe absent (ex. legacy/scaffold).
fn stub_decrypt_note(ciphertext: &[u8]) -> Option<String> {
    let prefix = b"STUB_ENC:";
    let payload = ciphertext.strip_prefix(prefix.as_ref())?;
    let plain: Vec<u8> = payload.iter().map(|b| b ^ 0xFF).collect();
    String::from_utf8(plain).ok()
}

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
                    AND ca.cabinet_id = cs.cabinet_id) AS acts_count \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         LEFT JOIN patient pat ON pat.id = a.patient_id \
                               AND pat.cabinet_id = cs.cabinet_id \
         LEFT JOIN provider prov ON prov.practitioner_id = cs.practitioner_id \
                                 AND prov.cabinet_id = cs.cabinet_id \
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
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(ConsultationListResponse { data }))
}
