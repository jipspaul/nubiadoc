//! Handlers avis praticiens : POST /v1/reviews (patient auth),
//! GET /v1/providers/:id/reviews (public) + PATCH /v1/cabinet/reviews/:id (modération).

use axum::{
    extract::{Path, Query, State},
    http::{HeaderMap, StatusCode},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProSecretaryPlusClaims},
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
    // #4410 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    if let Some(comment) = &body.comment {
        crate::text_validation::reject_nul_byte(comment)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient pour appointment_patient_read (policy 0029) → 404 si autre patient.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Empreinte de la requête : une clé rejouée avec un appointment_id/rating/comment
    // différent ne doit jamais renvoyer silencieusement l'avis de la 1re requête
    // (#3671, jumeau de #3632/#3620) -> divergence d'empreinte -> 409.
    let fingerprint = format!(
        "appointment={}|rating={}|comment={}",
        body.appointment_id,
        body.rating,
        body.comment.as_deref().unwrap_or(""),
    );

    // Idempotence : retourner l'avis existant si même patient + même clé + même empreinte.
    let existing = sqlx::query(
        "SELECT id, status, idempotency_fingerprint FROM review \
         WHERE patient_account_id = $1 AND idempotency_key = $2",
    )
    .bind(claims.account_id)
    .bind(&idempotency_key)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(row) = existing {
        let cached_fingerprint: Option<String> = row
            .try_get("idempotency_fingerprint")
            .map_err(|_| AppError::Internal)?;
        if cached_fingerprint.as_deref() != Some(fingerprint.as_str()) {
            tx.commit().await.map_err(|_| AppError::Internal)?;
            tracing::warn!(
                account_id = %claims.account_id,
                "review idempotency key replayed with a different fingerprint"
            );
            return Err(AppError::IdempotencyKeyConflict);
        }

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

    // Seuls les RDV effectivement honorés (consultation terminée) peuvent
    // générer un avis (#4362 — `checked_in`/`in_progress` étaient
    // whitelistés à tort : un patient juste arrivé en salle d'attente, ou
    // dont la consultation n'est pas terminée, pouvait déjà noter le
    // praticien, en contradiction directe avec l'intention "effectivement
    // honorés" ci-dessus).
    if appt_status != "done" {
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
          status, author_display, idempotency_key, idempotency_fingerprint) \
         VALUES ($1, $2, $3, $4, $5, 'pending', $6, $7, $8) \
         RETURNING id, status",
    )
    .bind(provider_id)
    .bind(claims.account_id)
    .bind(body.appointment_id)
    .bind(body.rating)
    .bind(body.comment.as_deref())
    .bind(&author_display)
    .bind(&idempotency_key)
    .bind(&fingerprint)
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
    pub id: Uuid,
    pub provider_id: Uuid,
    pub rating: i32,
    pub comment: Option<String>,
    pub author_name: String,
    pub created_at: String,
    pub status: String,
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
    let offset = (page - 1).saturating_mul(per_page);

    // Provider inconnu OU non listé → 200 avec liste vide (et non 404). Endpoint
    // public de listing d'avis : une collection absente est une liste vide, pas une
    // ressource manquante ; ça évite aussi de révéler l'existence d'un provider non
    // listé via 404-vs-200. Décision produit 2026-08-04.
    let provider_visible = sqlx::query!(
        "SELECT id FROM provider WHERE id = $1 AND is_listed = true",
        provider_id
    )
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .is_some();

    if !provider_visible {
        return Ok(Json(ListReviewsResponse {
            data: Vec::new(),
            page: PageInfo {
                page,
                per_page,
                total: 0,
            },
        }));
    }

    // Requête de comptage séparée de la requête paginée (#3864, même classe que
    // #3840 sur marketplace.rs::search_providers) : `COUNT(*) OVER()` est porté
    // par les LIGNES RETOURNÉES elles-mêmes — une page hors plage (OFFSET ≥ nb
    // d'avis) ne renvoie aucune ligne, donc `total` retombait à 0 au lieu du
    // vrai décompte global, indépendamment de la page demandée.
    let total: i64 = sqlx::query(
        "SELECT COUNT(*) AS total_count FROM review \
         WHERE provider_id = $1 AND status = 'published'",
    )
    .bind(provider_id)
    .fetch_one(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .try_get("total_count")
    .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, provider_id, rating, comment, \
                created_at, author_display, status \
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

    for row in &rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let provider_id: Uuid = row.try_get("provider_id").map_err(|_| AppError::Internal)?;
        let rating: i32 = row.try_get("rating").map_err(|_| AppError::Internal)?;
        let comment: Option<String> = row.try_get("comment").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        let author_name: String = row
            .try_get("author_display")
            .map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;

        data.push(ReviewItem {
            id,
            provider_id,
            rating,
            comment,
            author_name,
            created_at: created_at.to_rfc3339(),
            status,
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

// ── PATCH /v1/cabinet/reviews/:id ────────────────────────────────────────────

/// Corps de la requête `PATCH /v1/cabinet/reviews/:id`.
#[derive(Deserialize)]
pub struct ModerateReviewBody {
    /// `published` ou `rejected` (transition depuis `pending`, cf. policy RLS `review_app_update`).
    pub status: String,
}

/// Réponse de `PATCH /v1/cabinet/reviews/:id`.
#[derive(Serialize)]
pub struct ModerateReviewResponse {
    pub review_id: Uuid,
    pub status: String,
}

/// `PATCH /v1/cabinet/reviews/:id` — modération d'un avis (praticien ou secrétariat).
///
/// Token pro requis (praticien ou secrétaire, `ProSecretaryPlusClaims`).
/// `status` du body doit être `published` ou `rejected` → `422` sinon.
/// L'avis doit appartenir à un provider du cabinet du token → `404` sinon.
/// Transition applicable uniquement depuis `pending` (avis déjà modéré → `404`,
/// pas de re-modération pour éviter d'écraser une décision existante).
pub async fn moderate_review(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(review_id): Path<Uuid>,
    Json(body): Json<ModerateReviewBody>,
) -> Result<Json<ModerateReviewResponse>, AppError> {
    if !matches!(body.status.as_str(), "published" | "rejected") {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope cabinet (policy review_cabinet_moderate_read, migration 0137) : sans ce
    // GUC, l'avis 'pending' n'est visible par aucune policy SELECT et l'UPDATE ne
    // trouve donc jamais la ligne (404 systématique).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE review SET status = $1 \
         WHERE id = $2 AND status = 'pending' \
           AND provider_id IN (SELECT id FROM provider WHERE cabinet_id = $3) \
         RETURNING id, status, provider_id",
    )
    .bind(&body.status)
    .bind(review_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let review_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let provider_id: Uuid = row.try_get("provider_id").map_err(|_| AppError::Internal)?;

    // Recalcule l'agrégat affiché du praticien (carte annuaire + tri marketplace)
    // à partir des avis effectivement publiés, plutôt que de garder les colonnes
    // dénormalisées figées à leur valeur de seed.
    sqlx::query(
        "UPDATE provider SET \
           rating_avg = (SELECT avg(rating)::numeric(2,1) FROM review \
                         WHERE provider_id = $1 AND status = 'published'), \
           rating_count = (SELECT count(*) FROM review \
                            WHERE provider_id = $1 AND status = 'published') \
         WHERE id = $1",
    )
    .bind(provider_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.sub,
        review_id = %review_id,
        status = %status,
        "review moderated"
    );

    Ok(Json(ModerateReviewResponse { review_id, status }))
}

/// Détecte une violation de contrainte UNIQUE Postgres (code SQLSTATE `23505`),
/// par opposition à une autre erreur DB (connexion, contrainte CHECK, etc.).
/// Permet de distinguer un doublon légitime (→ 409) d'une vraie panne (→ 500).
/// Réutilisé par `billing.rs` pour `payment_idempotency_key_unique` (#3867).
pub(crate) fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}
