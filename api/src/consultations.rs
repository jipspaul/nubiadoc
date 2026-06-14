//! Handlers `/v1/cabinet/consultations/:id` — contexte et complétion d'une séance.

use axum::{
    extract::{Path, State},
    http::StatusCode,
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
    /// Note clinique déchiffrée. `None` si aucune note ou clé KMS non disponible (NUB-T3).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
    pub acts: Vec<ConsultationActItem>,
}

/// `GET /v1/cabinet/consultations/:id` — contexte clinique d'une séance au fauteuil.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// Note clinique : déchiffrée côté serveur via `core/crypto` (NUB-T3 — `None` si scaffold).
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

    // Note : déchiffrement via core/crypto (NUB-T3). Pour l'instant le crate est un
    // scaffold (CryptoError::NotImplemented) → on retourne None si ciphertext présent.
    let note: Option<String> = if note_ciphertext.is_some() {
        // TODO(NUB-T3) : appeler core_crypto::decrypt_column(ciphertext, key_ref, kms).
        None
    } else {
        None
    };

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

        // Crée les lignes du devis.
        for row in &act_rows {
            let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
            let ccam_code: Option<String> =
                row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
            let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
            let amount_cents: i32 = row
                .try_get("amount_cents")
                .map_err(|_| AppError::Internal)?;

            sqlx::query(
                "INSERT INTO quote_item \
                 (cabinet_id, quote_id, label, ccam_code, tooth, qty, unit_amount) \
                 VALUES ($1, $2, $3, $4, $5, 1, $6::numeric / 100)",
            )
            .bind(claims.cabinet_id)
            .bind(quote_id)
            .bind(&label)
            .bind(&ccam_code)
            .bind(&tooth)
            .bind(i64::from(amount_cents))
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

// ── POST /v1/cabinet/consultations/:id/acts ───────────────────────────────────

/// Corps de la requête `POST /v1/cabinet/consultations/:id/acts`.
#[derive(Deserialize)]
pub struct AddActBody {
    pub ccam_code: String,
    pub label: String,
    pub tooth: Option<String>,
    pub amount_cents: Option<i32>,
    /// Code acte sécurité sociale — accepté, non stocké (pas de colonne dédiée dans cette version).
    #[allow(dead_code)]
    pub secu_code: Option<String>,
    /// Réservé pour le devis (inclus/hors-nomenclature) — accepté, non stocké dans cette version.
    #[allow(dead_code)]
    pub included: Option<bool>,
}

/// Réponse de `POST /v1/cabinet/consultations/:id/acts`.
#[derive(Serialize)]
pub struct AddActResponse {
    pub act_id: Uuid,
}

/// `POST /v1/cabinet/consultations/:id/acts` — ajoute un acte CCAM à la séance.
///
/// Praticien uniquement (R.4127-72, §07 §4.1) — secrétaire → 403.
/// `cabinet_id` extrait du JWT, jamais du path/query (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`.
/// - Vérifie que la séance existe et appartient au cabinet du token.
/// - Insère dans `consultation_act` (RLS garantit le scope tenant).
/// - Retourne `201 { act_id }`.
/// - Body invalide (ccam_code vide, amount_cents < 0) → 422.
/// - Séance inexistante ou hors tenant → 404.
pub async fn add_consultation_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<AddActBody>,
) -> Result<(StatusCode, Json<AddActResponse>), AppError> {
    // Validation basique du body.
    if body.ccam_code.trim().is_empty() || body.label.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    if let Some(cents) = body.amount_cents {
        if cents < 0 {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que la séance existe, appartient au cabinet et récupère appointment_id +
    // practitioner_id + statut pour les gardes métier.
    let session_row = sqlx::query(
        "SELECT cs.appointment_id, cs.practitioner_id, cs.status, a.patient_id \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = session_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien qui a démarré la séance peut y ajouter des actes.
    // On compare le practitioner.user_id avec claims.sub.
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

    // La séance doit être en cours pour accepter de nouveaux actes.
    if session_status != "in_progress" {
        return Err(AppError::InvalidStatus);
    }

    let amount_cents = body.amount_cents.unwrap_or(0);

    let act_row = sqlx::query(
        "INSERT INTO consultation_act \
         (cabinet_id, appointment_id, patient_id, practitioner_id, \
          ccam_code, label, tooth, amount_cents) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(appointment_id)
    .bind(patient_id)
    .bind(practitioner_id)
    .bind(body.ccam_code.trim())
    .bind(body.label.trim())
    .bind(body.tooth.as_deref())
    .bind(amount_cents)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let act_id: Uuid = act_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        act_id = %act_id,
        "consultation act added"
    );

    Ok((StatusCode::CREATED, Json(AddActResponse { act_id })))
}
