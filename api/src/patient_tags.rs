//! Handlers `GET/POST /v1/cabinet/patients/:id/tags`,
//! `DELETE /v1/cabinet/patients/:id/tags/:tag_id` — étiquettes administratives
//! patient (#4040, table `patient_tag`, migration 0158).

use axum::{
    extract::{Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

/// Garde de scope secrétariat (R10) : un secrétaire ne peut agir sur les tags
/// d'un patient que s'il est joignable via `provider_secretariat` — même
/// requête que `patient_detail.rs:293-312` et `cabinet_document_download.rs`
/// (#3821/#3823). Sans cette garde, les tags fuient un patient que la fiche
/// et les documents masquent déjà en 404 (#4443).
pub(crate) async fn ensure_secretary_scope(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    claims: &ProSecretaryPlusClaims,
    patient_id: Uuid,
) -> Result<(), AppError> {
    if claims.role != "secretary" {
        return Ok(());
    }
    let in_scope = match claims.secretariat_id {
        Some(secretariat_id) => sqlx::query(
            "SELECT 1 FROM appointment a \
             JOIN provider pr ON pr.practitioner_id = a.practitioner_id \
             JOIN provider_secretariat ps ON ps.provider_id = pr.id \
             WHERE a.patient_id = $1 \
               AND a.deleted_at IS NULL \
               AND a.status <> 'cancelled' \
               AND ps.secretariat_id = $2 \
               AND ps.active = true",
        )
        .bind(patient_id)
        .bind(secretariat_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
        .is_some(),
        None => false,
    };
    if !in_scope {
        return Err(AppError::NotFound);
    }
    Ok(())
}

#[derive(Serialize)]
pub struct PatientTagItem {
    pub id: Uuid,
    pub label: String,
    pub color: String,
    pub created_by: Uuid,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct ListPatientTagsResponse {
    pub data: Vec<PatientTagItem>,
}

/// Vérifie que `patient_id` existe dans le cabinet courant (RLS déjà scopée
/// par `app.current_cabinet_id`). 404 anti-énumération sinon — même garde
/// que les autres routes `/cabinet/patients/:id/...`.
async fn ensure_patient_in_cabinet(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    cabinet_id: Uuid,
) -> Result<(), AppError> {
    let exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if exists.is_none() {
        return Err(AppError::NotFound);
    }
    Ok(())
}

/// `GET /v1/cabinet/patients/:id/tags` — liste les étiquettes administratives
/// d'un patient. Token pro requis (secretary+). RLS via `app.current_cabinet_id`.
pub async fn list_patient_tags(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<ListPatientTagsResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_patient_in_cabinet(&mut tx, patient_id, claims.cabinet_id).await?;
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    let rows = sqlx::query(
        "SELECT id, label, color, created_by, created_at FROM patient_tag \
         WHERE patient_id = $1 ORDER BY created_at DESC",
    )
    .bind(patient_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        let color: String = row.try_get("color").map_err(|_| AppError::Internal)?;
        let created_by: Uuid = row.try_get("created_by").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        data.push(PatientTagItem {
            id,
            label,
            color,
            created_by,
            created_at: created_at.to_rfc3339(),
        });
    }

    Ok(Json(ListPatientTagsResponse { data }))
}

/// Corps de la requête `POST /v1/cabinet/patients/:id/tags`.
#[derive(Deserialize)]
pub struct CreatePatientTagBody {
    pub label: String,
    pub color: Option<String>,
}

/// `color` doit être un hex `#RRGGBB` (6 chiffres) — une valeur arbitraire
/// acceptée verbatim casse le rendu de la puce côté front (#4395).
fn is_valid_hex_color(color: &str) -> bool {
    color.len() == 7 && color.starts_with('#') && color[1..].chars().all(|c| c.is_ascii_hexdigit())
}

/// `POST /v1/cabinet/patients/:id/tags` — pose une étiquette administrative.
///
/// Token pro requis (secretary+). `label` vide (après trim) ou contenant un
/// caractère de contrôle (ex. NUL, qui ferait échouer l'INSERT Postgres en
/// 500), ou `color` qui n'est pas un hex `#RRGGBB` → `422
/// {"code":"validation_error"}` (#4395). Patient hors cabinet → 404. Auditée
/// (`create_patient_tag`) dans `audit_log`.
pub async fn create_patient_tag(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<CreatePatientTagBody>,
) -> Result<(StatusCode, Json<PatientTagItem>), AppError> {
    let label = body.label.trim().to_string();
    if label.is_empty() || label.chars().any(|c| c.is_control()) {
        return Err(AppError::ValidationError);
    }
    let color = body
        .color
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or("#94A3B8")
        .to_string();
    if !is_valid_hex_color(&color) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_patient_in_cabinet(&mut tx, patient_id, claims.cabinet_id).await?;
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    let row = sqlx::query(
        "INSERT INTO patient_tag (cabinet_id, patient_id, label, color, created_by) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, created_at",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&label)
    .bind(&color)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let tag_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'create_patient_tag', 'patient_tag', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(tag_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        tag_id = %tag_id,
        "patient tag created"
    );

    Ok((
        StatusCode::CREATED,
        Json(PatientTagItem {
            id: tag_id,
            label,
            color,
            created_by: claims.sub,
            created_at: created_at.to_rfc3339(),
        }),
    ))
}

/// `DELETE /v1/cabinet/patients/:id/tags/:tag_id` — retire une étiquette.
///
/// Token pro requis (secretary+). Étiquette absente ou hors patient/cabinet
/// → 404. Auditée (`delete_patient_tag`) dans `audit_log`.
pub async fn delete_patient_tag(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path((patient_id, tag_id)): Path<(Uuid, Uuid)>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    ensure_patient_in_cabinet(&mut tx, patient_id, claims.cabinet_id).await?;
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    let deleted =
        sqlx::query("DELETE FROM patient_tag WHERE id = $1 AND patient_id = $2 RETURNING id")
            .bind(tag_id)
            .bind(patient_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'delete_patient_tag', 'patient_tag', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(tag_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        tag_id = %tag_id,
        "patient tag deleted"
    );

    Ok(StatusCode::NO_CONTENT)
}
