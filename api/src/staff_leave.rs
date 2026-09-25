//! Workflow congés (DP-F27.b, #7144) sur `leave_request` (#7145, migration
//! 0300) : demande (soi-même) → validation manager (`ProAdminOrManagerClaims`,
//! admin/manager) → `approved`/`rejected`, ou annulation par le demandeur.
//! Un `leave_request.status = 'approved'` EST l'indisponibilité (pas de
//! duplication vers `provider_unavailability`, qui est scopée `provider`,
//! pas `app_user` — modèle différent). Extrait de `staff.rs` (plafond de
//! taille par fichier — même choix que `appointments_checkin.rs`).

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminOrManagerClaims, ProSecretaryPlusClaims},
    staff::{audit, parse_instant},
    AppState,
};

const LEAVE_KINDS: [&str; 4] = ["paid_leave", "unpaid_leave", "sick_leave", "other"];
const LEAVE_STATUSES: [&str; 4] = ["pending", "approved", "rejected", "cancelled"];

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateLeaveRequestBody {
    pub starts_at: String,
    pub ends_at: String,
    pub kind: String,
}

#[derive(Serialize)]
pub struct LeaveRequestItem {
    pub id: Uuid,
    pub user_id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub kind: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub decided_by: Option<Uuid>,
}

fn leave_row_to_item(row: &sqlx::postgres::PgRow) -> Result<LeaveRequestItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
    let starts_at: DateTime<Utc> = row.try_get("starts_at").map_err(|_| AppError::Internal)?;
    let ends_at: DateTime<Utc> = row.try_get("ends_at").map_err(|_| AppError::Internal)?;
    let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let decided_by: Option<Uuid> = row.try_get("decided_by").map_err(|_| AppError::Internal)?;
    Ok(LeaveRequestItem {
        id,
        user_id,
        starts_at: starts_at.to_rfc3339(),
        ends_at: ends_at.to_rfc3339(),
        kind,
        status,
        decided_by,
    })
}

/// `POST /v1/cabinet/staff/leave-requests` — demande de congé pour
/// SOI-MÊME (`user_id` = `claims.sub`, jamais du corps : une demande de
/// congé au nom d'autrui n'a pas de sens métier). `kind` hors énum ou
/// `ends_at <= starts_at` → 422. Statut initial `pending`.
pub async fn create_leave_request(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateLeaveRequestBody>,
) -> Result<(StatusCode, Json<LeaveRequestItem>), AppError> {
    if !LEAVE_KINDS.contains(&body.kind.as_str()) {
        return Err(AppError::ValidationError);
    }
    let starts_at = parse_instant(&body.starts_at)?;
    let ends_at = parse_instant(&body.ends_at)?;
    if ends_at <= starts_at {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO leave_request (cabinet_id, user_id, starts_at, ends_at, kind) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, user_id, starts_at, ends_at, kind, status, decided_by",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(starts_at)
    .bind(ends_at)
    .bind(&body.kind)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = leave_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "create_leave_request",
        "leave_request",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        leave_request_id = %item.id,
        "leave request created"
    );

    Ok((StatusCode::CREATED, Json(item)))
}

/// Query de `GET /v1/cabinet/staff/leave-requests`.
#[derive(Deserialize)]
pub struct ListLeaveRequestsQuery {
    pub user_id: Option<Uuid>,
    pub status: Option<String>,
}

/// `GET /v1/cabinet/staff/leave-requests` — `practitioner` ne voit que ses
/// propres demandes (`user_id` forcé à `claims.sub`, tout filtre `user_id`
/// du client ignoré) ; secretary/admin/manager/doctor voient tout le
/// cabinet, filtrable par `user_id`/`status`. `status` hors énum → 422.
pub async fn list_leave_requests(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListLeaveRequestsQuery>,
) -> Result<Json<Vec<LeaveRequestItem>>, AppError> {
    if let Some(status) = &params.status {
        if !LEAVE_STATUSES.contains(&status.as_str()) {
            return Err(AppError::ValidationError);
        }
    }
    let user_filter = if claims.role == "practitioner" {
        Some(claims.sub)
    } else {
        params.user_id
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, user_id, starts_at, ends_at, kind, status, decided_by FROM leave_request \
         WHERE ($1::uuid IS NULL OR user_id = $1) \
           AND ($2::text IS NULL OR status = $2) \
         ORDER BY starts_at DESC",
    )
    .bind(user_filter)
    .bind(params.status)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    rows.iter()
        .map(leave_row_to_item)
        .collect::<Result<Vec<_>, _>>()
        .map(Json)
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct DecideLeaveRequestBody {
    pub approve: bool,
}

/// `POST /v1/cabinet/staff/leave-requests/:id/decide` — validation manager
/// (`ProAdminOrManagerClaims` : admin/manager uniquement, secretary/practitioner
/// → 403). Doit être `pending` → sinon `409 invalid_status` (déjà décidé ou
/// annulé). Passe `approved`/`rejected`, `decided_by = claims.sub`.
pub async fn decide_leave_request(
    State(state): State<AppState>,
    claims: ProAdminOrManagerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<DecideLeaveRequestBody>,
) -> Result<Json<LeaveRequestItem>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT status FROM leave_request WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if status != "pending" {
        return Err(AppError::InvalidStatus);
    }

    let new_status = if body.approve { "approved" } else { "rejected" };
    let row = sqlx::query(
        "UPDATE leave_request SET status = $1, decided_by = $2, updated_at = now() \
         WHERE id = $3 \
         RETURNING id, user_id, starts_at, ends_at, kind, status, decided_by",
    )
    .bind(new_status)
    .bind(claims.sub)
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = leave_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "decide_leave_request",
        "leave_request",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        leave_request_id = %item.id,
        status = %new_status,
        "leave request decided"
    );

    Ok(Json(item))
}

/// `POST /v1/cabinet/staff/leave-requests/:id/cancel` — le demandeur annule
/// sa propre demande (`pending` ou `approved` → `cancelled`) ; toute autre
/// personne → 403 ; statut `rejected`/`cancelled` → 409 `invalid_status`.
pub async fn cancel_leave_request(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<LeaveRequestItem>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT user_id, status FROM leave_request WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let user_id: Uuid = existing
        .try_get("user_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = existing.try_get("status").map_err(|_| AppError::Internal)?;
    if user_id != claims.sub {
        return Err(AppError::Forbidden);
    }
    if status != "pending" && status != "approved" {
        return Err(AppError::InvalidStatus);
    }

    let row = sqlx::query(
        "UPDATE leave_request SET status = 'cancelled', updated_at = now() \
         WHERE id = $1 \
         RETURNING id, user_id, starts_at, ends_at, kind, status, decided_by",
    )
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = leave_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "cancel_leave_request",
        "leave_request",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(item))
}
