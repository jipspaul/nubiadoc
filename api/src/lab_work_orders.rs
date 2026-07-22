//! Handlers bons de travaux prothétiques (#4148), sur `lab_work_order`
//! (migration 0193, #4147) :
//! - `GET/POST /v1/cabinet/lab-work-orders`
//! - `PATCH /v1/cabinet/lab-work-orders/:id`
//!
//! `ProPractitionerClaims` (pas `ProSecretaryPlusClaims`) : le suivi
//! prothétique engage le praticien (choix du laboratoire, validation de
//! l'essayage/pose), même pattern que `prescriptions.rs`.

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
    notify, AppState,
};

/// Ordre de progression légal — une transition n'est autorisée que vers un
/// statut de rang STRICTEMENT supérieur (retour arrière interdit, cf. #4148 :
/// `sent → returned` autorisé (saute `try_in`), `fitted → sent` refusé).
const STATUS_ORDER: [&str; 4] = ["sent", "try_in", "returned", "fitted"];

fn is_forward_transition(current: &str, target: &str) -> bool {
    let (Some(from), Some(to)) = (
        STATUS_ORDER.iter().position(|s| *s == current),
        STATUS_ORDER.iter().position(|s| *s == target),
    ) else {
        return false;
    };
    to > from
}

// ── GET/POST /v1/cabinet/lab-work-orders ─────────────────────────────────────

/// Un bon de travail prothétique.
#[derive(Serialize)]
pub struct LabWorkOrderDto {
    pub id: Uuid,
    pub patient_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub quote_item_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub appointment_id: Option<Uuid>,
    pub lab_name: String,
    pub purchase_price_cents: i32,
    pub status: String,
    pub sent_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub expected_return_at: Option<String>,
}

/// `GET /v1/cabinet/lab-work-orders` — liste les bons du cabinet, du plus
/// récent au plus ancien.
pub async fn list_lab_work_orders(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<Vec<LabWorkOrderDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, patient_id, quote_item_id, appointment_id, lab_name, \
         purchase_price_cents, status, sent_at, expected_return_at \
         FROM lab_work_order \
         WHERE cabinet_id = $1 \
         ORDER BY sent_at DESC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut orders = Vec::with_capacity(rows.len());
    for row in &rows {
        let sent_at: chrono::DateTime<chrono::Utc> =
            row.try_get("sent_at").map_err(|_| AppError::Internal)?;
        let expected_return_at: Option<chrono::DateTime<chrono::Utc>> = row
            .try_get("expected_return_at")
            .map_err(|_| AppError::Internal)?;
        orders.push(LabWorkOrderDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            patient_id: row.try_get("patient_id").map_err(|_| AppError::Internal)?,
            quote_item_id: row
                .try_get("quote_item_id")
                .map_err(|_| AppError::Internal)?,
            appointment_id: row
                .try_get("appointment_id")
                .map_err(|_| AppError::Internal)?,
            lab_name: row.try_get("lab_name").map_err(|_| AppError::Internal)?,
            purchase_price_cents: row
                .try_get("purchase_price_cents")
                .map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
            sent_at: sent_at.to_rfc3339(),
            expected_return_at: expected_return_at.map(|d| d.to_rfc3339()),
        });
    }

    Ok(Json(orders))
}

/// Body de `POST /v1/cabinet/lab-work-orders`.
#[derive(Deserialize)]
pub struct CreateLabWorkOrderBody {
    pub patient_id: Uuid,
    pub quote_item_id: Option<Uuid>,
    pub appointment_id: Option<Uuid>,
    pub lab_name: String,
    pub purchase_price_cents: i32,
}

/// Réponse de `POST /v1/cabinet/lab-work-orders`.
#[derive(Serialize)]
pub struct CreateLabWorkOrderResponse {
    pub order_id: Uuid,
}

/// `POST /v1/cabinet/lab-work-orders` — crée un bon de travail (statut
/// `sent` par défaut).
///
/// `lab_name` non vide, `purchase_price_cents >= 0` → 422 sinon (déclaration
/// du prix d'achat obligatoire, #4147). `patient_id` (et `quote_item_id`/
/// `appointment_id` si fournis) doivent exister dans ce cabinet → 404 sinon
/// (FK composite (id, cabinet_id), migration 0193 — pré-vérifié pour ne pas
/// laisser remonter la contrainte en 500, cf. précédent `sterilization.rs`).
pub async fn create_lab_work_order(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateLabWorkOrderBody>,
) -> Result<(StatusCode, Json<CreateLabWorkOrderResponse>), AppError> {
    if body.lab_name.trim().is_empty() || body.purchase_price_cents < 0 {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query("SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2")
        .bind(body.patient_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    if let Some(quote_item_id) = body.quote_item_id {
        let exists = sqlx::query("SELECT 1 FROM quote_item WHERE id = $1 AND cabinet_id = $2")
            .bind(quote_item_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    if let Some(appointment_id) = body.appointment_id {
        let exists = sqlx::query("SELECT 1 FROM appointment WHERE id = $1 AND cabinet_id = $2")
            .bind(appointment_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        if exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let row = sqlx::query(
        "INSERT INTO lab_work_order \
         (cabinet_id, patient_id, quote_item_id, appointment_id, lab_name, purchase_price_cents) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.patient_id)
    .bind(body.quote_item_id)
    .bind(body.appointment_id)
    .bind(body.lab_name.trim())
    .bind(body.purchase_price_cents)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let order_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        order_id = %order_id,
        "lab work order created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateLabWorkOrderResponse { order_id }),
    ))
}

// ── PATCH /v1/cabinet/lab-work-orders/:id ─────────────────────────────────────

/// Body de `PATCH /v1/cabinet/lab-work-orders/:id`.
#[derive(Deserialize)]
pub struct PatchLabWorkOrderBody {
    pub status: String,
}

/// Réponse de `PATCH /v1/cabinet/lab-work-orders/:id`.
#[derive(Serialize)]
pub struct PatchLabWorkOrderResponse {
    pub status: String,
}

/// `PATCH /v1/cabinet/lab-work-orders/:id` — fait progresser le statut.
///
/// Bon inexistant/hors tenant → 404. Transition vers un statut de rang
/// inférieur ou égal (retour arrière, statut inconnu) →
/// `409 invalid_status` — la progression n'a pas besoin d'être séquentielle
/// (`sent → returned` saute `try_in`), seulement croissante (#4148).
///
/// Passage à `returned` (#4165) : notification in-app au patient concerné
/// ("votre prothèse est arrivée"), via `app_user_id` direct sinon via le
/// compte patient rattaché — même pattern dual-path que
/// `consultations.rs::complete_consultation` (#4152). Patient sans compte →
/// silencieusement aucune notification, pas une erreur.
pub async fn patch_lab_work_order(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchLabWorkOrderBody>,
) -> Result<Json<PatchLabWorkOrderResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT status, patient_id FROM lab_work_order WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let current_status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;

    if !is_forward_transition(&current_status, &body.status) {
        return Err(AppError::InvalidStatus);
    }

    sqlx::query("UPDATE lab_work_order SET status = $1 WHERE id = $2 AND cabinet_id = $3")
        .bind(&body.status)
        .bind(id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if body.status == "returned" {
        let patient_row =
            sqlx::query("SELECT app_user_id, patient_account_id FROM patient WHERE id = $1")
                .bind(patient_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if let Some(patient_row) = patient_row {
            let patient_app_user_id: Option<Uuid> = patient_row
                .try_get("app_user_id")
                .map_err(|_| AppError::Internal)?;
            let patient_account_id: Option<Uuid> = patient_row
                .try_get("patient_account_id")
                .map_err(|_| AppError::Internal)?;
            let title = "Votre prothèse est arrivée au cabinet.";
            let data = serde_json::json!({ "order_id": id });
            if let Some(uid) = patient_app_user_id {
                notify::notify_user(&mut tx, uid, "lab_work_returned", title, data).await?;
            } else if let Some(account_id) = patient_account_id {
                notify::notify_patient_account(
                    &mut tx,
                    account_id,
                    "lab_work_returned",
                    title,
                    data,
                )
                .await?;
            }
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        order_id = %id,
        from = %current_status,
        to = %body.status,
        "lab work order status updated"
    );

    Ok(Json(PatchLabWorkOrderResponse {
        status: body.status,
    }))
}
