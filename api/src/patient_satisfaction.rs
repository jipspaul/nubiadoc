//! Agrégat de satisfaction patient (#4161) — appelé par
//! `patient_detail::get_cabinet_patient` (`PatientAdminSection.satisfaction`).
//!
//! Quoi : note moyenne + dernier avis laissés par un patient, scopés au
//! cabinet courant (un `review` est rattaché à un `provider`, qui appartient
//! à un cabinet — on n'agrège que les avis envers CE cabinet, jamais les avis
//! laissés ailleurs sur la plateforme, pour ne pas faire fuiter de données
//! d'un cabinet vers un autre via la fiche patient).
//! Pourquoi cette approche : module dédié plutôt qu'ajout direct dans
//! `clinical.rs` (1853 lignes, déjà largement au-dessus du plafond absolu
//! CLAUDE.md — un refactor de taille est nécessaire mais hors scope de cette
//! issue ; ajout minimal ici : un import + un appel + un champ de réponse).
//! Modes d'échec : `status != 'published'` exclu (avis en modération/rejeté
//! non pertinent pour un signal affiché au cabinet) ; aucun avis → `None`.

use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;

/// Dernier avis publié (rating/commentaire/date).
#[derive(serde::Serialize)]
pub struct LastReviewSummary {
    pub rating: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub comment: Option<String>,
    pub created_at: String,
}

/// Agrégat de satisfaction exposé sur `GET /v1/cabinet/patients/:id`.
#[derive(serde::Serialize)]
pub struct PatientSatisfactionSummary {
    pub avg_rating: f64,
    pub review_count: i64,
    pub last_review: LastReviewSummary,
}

/// Agrège les avis `published` laissés par `patient_account_id` envers les
/// providers du cabinet `cabinet_id`. `None` si aucun avis.
pub(crate) async fn aggregate_patient_satisfaction(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_account_id: Uuid,
    cabinet_id: Uuid,
) -> Result<Option<PatientSatisfactionSummary>, AppError> {
    let agg_row = sqlx::query(
        "SELECT AVG(r.rating)::float8 AS avg_rating, COUNT(*) AS review_count \
         FROM review r \
         JOIN provider p ON p.id = r.provider_id \
         WHERE r.patient_account_id = $1 AND p.cabinet_id = $2 AND r.status = 'published'",
    )
    .bind(patient_account_id)
    .bind(cabinet_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let review_count: i64 = agg_row
        .try_get("review_count")
        .map_err(|_| AppError::Internal)?;
    if review_count == 0 {
        return Ok(None);
    }
    let avg_rating: f64 = agg_row
        .try_get("avg_rating")
        .map_err(|_| AppError::Internal)?;

    let last_row = sqlx::query(
        "SELECT r.rating, r.comment, r.created_at \
         FROM review r \
         JOIN provider p ON p.id = r.provider_id \
         WHERE r.patient_account_id = $1 AND p.cabinet_id = $2 AND r.status = 'published' \
         ORDER BY r.created_at DESC, r.id DESC \
         LIMIT 1",
    )
    .bind(patient_account_id)
    .bind(cabinet_id)
    .fetch_one(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let rating: i32 = last_row.try_get("rating").map_err(|_| AppError::Internal)?;
    let comment: Option<String> = last_row
        .try_get("comment")
        .map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> = last_row
        .try_get("created_at")
        .map_err(|_| AppError::Internal)?;

    Ok(Some(PatientSatisfactionSummary {
        avg_rating,
        review_count,
        last_review: LastReviewSummary {
            rating,
            comment,
            created_at: created_at.to_rfc3339(),
        },
    }))
}
