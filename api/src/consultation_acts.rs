//! Handlers `/v1/cabinet/consultations/:id/acts` — CRUD des actes CCAM d'une
//! séance au fauteuil.
//!
//! Extrait de `consultations.rs` (refactor de taille, cf. #4056 / CLAUDE.md
//! plafond 700 lignes) — module autonome, mêmes handlers/contrats, aucun
//! changement fonctionnel.

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
    consultations::ConsultationActItem,
    AppState,
};

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

// ── GET /v1/cabinet/consultations/:id/acts ────────────────────────────────────

/// Réponse de `GET /v1/cabinet/consultations/:id/acts`.
#[derive(Serialize)]
pub struct ListActsResponse {
    pub data: Vec<ConsultationActItem>,
}

/// `GET /v1/cabinet/consultations/:id/acts` — liste les actes CCAM d'une séance.
///
/// Praticien uniquement. `cabinet_id` extrait du JWT (invariant tenancy).
/// RLS tenant-scoped via `app.current_cabinet_id`. 404 si séance absente ou hors tenant.
/// Garde relation-de-soin E.2.16.c §14 (miroir `medical_record.rs`) : le praticien
/// appelant doit avoir eu au moins un `appointment` avec le patient de la séance,
/// sinon 403 — même s'il est dans le même cabinet.
pub async fn list_consultation_acts(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ListActsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que la séance existe et appartient au cabinet (RLS + filtre explicite).
    let session_row = sqlx::query(
        "SELECT appointment_id FROM consultation_session \
         WHERE id = $1 AND cabinet_id = $2",
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

    let mut data: Vec<ConsultationActItem> = Vec::with_capacity(act_rows.len());
    for row in act_rows {
        let act_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let ccam_code: String = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        let amount_cents: i32 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        data.push(ConsultationActItem {
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
        consultation_id = %id,
        count = data.len(),
        "consultation acts listed"
    );

    Ok(Json(ListActsResponse { data }))
}

// ── PATCH /v1/cabinet/consultations/:id/acts/:act_id ─────────────────────────

/// Corps de `PATCH /v1/cabinet/consultations/:id/acts/:act_id`.
#[derive(Deserialize)]
pub struct PatchActBody {
    pub label: Option<String>,
    pub tooth: Option<String>,
    pub amount_cents: Option<i32>,
}

/// Réponse de `PATCH /v1/cabinet/consultations/:id/acts/:act_id`.
#[derive(Serialize)]
pub struct PatchActResponse {
    pub act_id: Uuid,
}

/// `PATCH /v1/cabinet/consultations/:id/acts/:act_id` — modifie un acte CCAM.
///
/// Praticien uniquement, et seulement le praticien propriétaire de la séance
/// (comme `add_consultation_act`) — sinon 403. Séance doit être `in_progress`.
/// `cabinet_id` extrait du JWT. RLS tenant-scoped.
/// 404 si séance ou acte absents ou hors tenant.
pub async fn patch_consultation_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path((id, act_id)): Path<(Uuid, Uuid)>,
    Json(body): Json<PatchActBody>,
) -> Result<Json<PatchActResponse>, AppError> {
    if let Some(cents) = body.amount_cents {
        if cents < 0 {
            return Err(AppError::ValidationError);
        }
    }
    if body.label.as_deref().is_some_and(|s| s.trim().is_empty()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie séance + statut in_progress.
    let session_row = sqlx::query(
        "SELECT appointment_id, practitioner_id, status FROM consultation_session \
         WHERE id = $1 AND cabinet_id = $2",
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
    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien qui a démarré la séance peut en modifier les actes.
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

    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;

    // Met à jour l'acte (filtre sur appointment_id et cabinet_id pour la tenancy).
    let updated = sqlx::query(
        "UPDATE consultation_act \
         SET label        = COALESCE($1, label), \
             tooth        = COALESCE($2, tooth), \
             amount_cents = COALESCE($3, amount_cents) \
         WHERE id = $4 AND appointment_id = $5 AND cabinet_id = $6 \
         RETURNING id",
    )
    .bind(body.label.as_deref())
    .bind(body.tooth.as_deref())
    .bind(body.amount_cents)
    .bind(act_id)
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let updated_id: Uuid = updated.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        act_id = %updated_id,
        "consultation act patched"
    );

    Ok(Json(PatchActResponse { act_id: updated_id }))
}

// ── DELETE /v1/cabinet/consultations/:id/acts/:act_id ────────────────────────

/// `DELETE /v1/cabinet/consultations/:id/acts/:act_id` — supprime un acte CCAM.
///
/// Praticien uniquement, et seulement le praticien propriétaire de la séance
/// (comme `add_consultation_act`) — sinon 403. Séance doit être `in_progress`.
/// `cabinet_id` extrait du JWT. RLS tenant-scoped.
/// 404 si séance ou acte absents ou hors tenant.
pub async fn delete_consultation_act(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path((id, act_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie séance + statut in_progress.
    let session_row = sqlx::query(
        "SELECT appointment_id, practitioner_id, status FROM consultation_session \
         WHERE id = $1 AND cabinet_id = $2",
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
    let session_status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;

    // Seul le praticien qui a démarré la séance peut en supprimer les actes.
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

    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;

    // Supprime l'acte (filtre tenancy).
    let result = sqlx::query(
        "DELETE FROM consultation_act \
         WHERE id = $1 AND appointment_id = $2 AND cabinet_id = $3 \
         RETURNING id",
    )
    .bind(act_id)
    .bind(appointment_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if result.is_none() {
        return Err(AppError::NotFound);
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        act_id = %act_id,
        "consultation act deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
