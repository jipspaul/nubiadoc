//! Handlers avis praticiens : POST /v1/reviews (patient auth) + GET /v1/providers/:id/reviews (public).

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims},
    AppState,
};

// ── POST /v1/reviews ─────────────────────────────────────────────────────────

/// Corps de la requête `POST /v1/reviews`.
#[derive(Deserialize)]
pub struct CreateReviewBody {
    pub appointment_id: Uuid,
    /// Note de 1 à 5.
    pub rating: i32,
    pub comment: Option<String>,
}

/// Réponse de `POST /v1/reviews`.
#[derive(Serialize)]
pub struct CreateReviewResponse {
    pub review_id: Uuid,
    pub status: String,
}

/// `POST /v1/reviews` — patient soumet un avis sur un praticien.
///
/// Token `kind:"patient"` requis. `Idempotency-Key` obligatoire → `400` sinon.
/// Vérifie que l'appointment appartient au patient (RLS via `app.patient_account_id`) → `404`.
/// Vérifie que le statut est `done`, `checked_in` ou `in_progress` → `422` sinon.
/// Contrainte UNIQUE `review_appointment_unique` → `409 review_already_exists`.
/// Statut initial `pending` (modération avant publication).
/// `author_display` = `"Prénom N."` dérivé du compte patient.
pub async fn create_review(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    headers: HeaderMap,
    Json(body): Json<CreateReviewBody>,
) -> Result<(StatusCode, Json<CreateReviewResponse>), AppError> {
    // Idempotency-Key obligatoire.
    let idempotency_key = headers
        .get("idempotency-key")
        .and_then(|v| v.to_str().ok())
        .filter(|s| !s.is_empty())
        .map(|s| s.to_owned())
        .ok_or(AppError::MissingIdempotencyKey)?;

    if body.rating < 1 || body.rating > 5 {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Idempotence : retourner l'avis existant si même patient + même clé.
    let existing = sqlx::query(
        "SELECT id, status FROM review \
         WHERE patient_account_id = $1 AND idempotency_key = $2",
    )
    .bind(claims.account_id)
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(row) = existing {
        let review_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        return Ok((
            StatusCode::CREATED,
            Json(CreateReviewResponse { review_id, status }),
        ));
    }

    // Vérifie que l'appointment appartient au patient et est dans un statut honoré.
    // Jointure sur patient (pas patient_account) car la RLS patient_account_read
    // utilise app.patient_account_id qui est déjà posé, et patient.first_name/last_name
    // sont disponibles directement sans nécessiter app.current_account_id.
    let appt_row = sqlx::query(
        "SELECT a.id, a.status, a.cabinet_id, \
                pr.id AS provider_id, \
                pt.first_name, pt.last_name \
         FROM appointment a \
         JOIN patient pt  ON pt.id = a.patient_id \
         JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
         WHERE a.id = $1 AND a.deleted_at IS NULL",
    )
    .bind(body.appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let appt_status: String = appt_row.try_get("status").map_err(|_| AppError::Internal)?;

    // Seuls les RDV effectivement honorés peuvent générer un avis.
    if !matches!(appt_status.as_str(), "done" | "checked_in" | "in_progress") {
        return Err(AppError::AppointmentNotHonored);
    }

    let provider_id: Uuid = appt_row
        .try_get("provider_id")
        .map_err(|_| AppError::Internal)?;
    let first_name: String = appt_row
        .try_get("first_name")
        .map_err(|_| AppError::Internal)?;
    let last_name: String = appt_row
        .try_get("last_name")
        .map_err(|_| AppError::Internal)?;

    // author_display = "Prénom I." (initiale du nom, anonymisation légère).
    let initial = last_name.chars().next().unwrap_or('?');
    let author_display = format!("{} {}.", first_name, initial);

    // INSERT — contrainte UNIQUE review_appointment_unique → 409 si doublon.
    let result = sqlx::query(
        "INSERT INTO review \
         (provider_id, patient_account_id, appointment_id, rating, comment, \
          status, author_display, idempotency_key) \
         VALUES ($1, $2, $3, $4, $5, 'pending', $6, $7) \
         RETURNING id, status",
    )
    .bind(provider_id)
    .bind(claims.account_id)
    .bind(body.appointment_id)
    .bind(body.rating)
    .bind(body.comment.as_deref())
    .bind(&author_display)
    .bind(&idempotency_key)
    .fetch_one(&mut *tx)
    .await;

    let row = match result {
        Ok(row) => row,
        Err(e) if is_unique_violation(&e) => return Err(AppError::ReviewAlreadyExists),
        Err(_) => return Err(AppError::Internal),
    };

    let review_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        review_id = %review_id,
        provider_id = %provider_id,
        "review submitted"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateReviewResponse { review_id, status }),
    ))
}

// ── GET /v1/providers/:id/reviews ────────────────────────────────────────────

#[derive(Deserialize)]
pub struct ListReviewsQuery {
    pub page: Option<i64>,
    pub per_page: Option<i64>,
}

#[derive(Serialize)]
pub struct ReviewItem {
    pub rating: i32,
    pub comment: Option<String>,
    pub created_at: String,
    pub author_display: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub page: i64,
    pub per_page: i64,
    pub total: i64,
}

#[derive(Serialize)]
pub struct ListReviewsResponse {
    pub data: Vec<ReviewItem>,
    pub page: PageInfo,
}

/// `GET /v1/providers/:id/reviews` — avis publiés d'un praticien (public, pas de JWT).
///
/// Route publique : seuls les avis `published` sont exposés (RLS `review_public_read`).
/// Paginé (offset-based) : `page` + `per_page` (défaut 20, max 100).
/// Trié `created_at DESC`.
pub async fn list_provider_reviews(
    State(state): State<AppState>,
    Path(provider_id): Path<Uuid>,
    Query(params): Query<ListReviewsQuery>,
) -> Result<Json<ListReviewsResponse>, AppError> {
    let page = params.page.unwrap_or(1).max(1);
    let per_page = params.per_page.unwrap_or(20).clamp(1, 100);
    let offset = (page - 1) * per_page;

    let rows = sqlx::query(
        "SELECT rating, comment, created_at, author_display, \
                COUNT(*) OVER() AS total_count \
         FROM review \
         WHERE provider_id = $1 AND status = 'published' \
         ORDER BY created_at DESC \
         LIMIT $2 OFFSET $3",
    )
    .bind(provider_id)
    .bind(per_page)
    .bind(offset)
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut data: Vec<ReviewItem> = Vec::with_capacity(rows.len());
    let mut total: i64 = 0;

    for row in &rows {
        if let Ok(n) = row.try_get::<i64, _>("total_count") {
            total = n;
        }
        let rating: i32 = row.try_get("rating").map_err(|_| AppError::Internal)?;
        let comment: Option<String> = row.try_get("comment").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let author_display: String = row
            .try_get("author_display")
            .map_err(|_| AppError::Internal)?;

        data.push(ReviewItem {
            rating,
            comment,
            created_at: created_at.to_rfc3339(),
            author_display,
        });
    }

    Ok(Json(ListReviewsResponse {
        data,
        page: PageInfo {
            page,
            per_page,
            total,
        },
    }))
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}
