//! Handlers `/v1/cabinet/consultations/:id/acts` — lecture/modification/
//! suppression des actes CCAM d'une séance au fauteuil. La création
//! (`POST`) vit dans `consultation_act_create.rs` (extraite d'ici, refactor
//! de taille, CLAUDE.md plafond 700 lignes).
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
    consultation_context::ConsultationActItem,
    AppState,
};

/// Valide un code dent ISO 3950 (notation FDI) : `<quadrant><dent>`,
/// quadrant 1-4 (dentition permanente, dents 1-8) ou 5-8 (temporaire, 1-5).
/// Même règle que `dental_chart.rs::validate_teeth` et
/// `treatment_phases.rs::is_valid_fdi_tooth` (#4426) — dupliquée ici faute de
/// module de validation partagé pour une fonction aussi courte.
fn is_valid_fdi_tooth(code: &str) -> bool {
    code.len() == 2 && code.chars().all(|c| c.is_ascii_digit()) && {
        let quadrant = code.as_bytes()[0] - b'0';
        let tooth = code.as_bytes()[1] - b'0';
        match quadrant {
            1..=4 => (1..=8).contains(&tooth),
            5..=8 => (1..=5).contains(&tooth),
            _ => false,
        }
    }
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
    // #4426 : un tooth doit être un code FDI valide, comme dental-chart et
    // les phases de plan de traitement.
    if let Some(tooth) = body.tooth.as_deref() {
        if !is_valid_fdi_tooth(tooth) {
            return Err(AppError::ValidationError);
        }
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

    // Refuse proprement (409) si l'acte est référencé par un mouvement de
    // stock ou une pochette de stérilisation : les FK composites
    // `(consultation_act_id, cabinet_id)` de `stock_movement` (migration
    // 0192) et `sterilized_pouch` (migration 0190) n'ont pas de clause
    // `ON DELETE`, un hard-delete sans ce garde-fou remonte en 500 (23503).
    let linked_row = sqlx::query(
        "SELECT EXISTS(\
           SELECT 1 FROM stock_movement \
           WHERE consultation_act_id = $1 AND cabinet_id = $2\
         ) OR EXISTS(\
           SELECT 1 FROM sterilized_pouch \
           WHERE consultation_act_id = $1 AND cabinet_id = $2\
         )",
    )
    .bind(act_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let linked_to_stock: bool = linked_row.try_get(0).map_err(|_| AppError::Internal)?;
    if linked_to_stock {
        return Err(AppError::ActLinkedToStock);
    }

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
