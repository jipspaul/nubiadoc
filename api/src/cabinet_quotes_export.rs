//! Handler `GET /v1/cabinet/quotes/export.csv` (#4154) — export CSV des
//! devis du cabinet.
//!
//! Réutilise le filtre `?status=` de `cabinet_quotes::list_cabinet_quotes`
//! (même énum `VALID_QUOTE_STATUSES`, même erreur `invalid_status_filter`).
//! Ajoute `?date_from=`/`?date_to=` (bornes inclusives sur `created_at`,
//! format `YYYY-MM-DD`) : absent de l'endpoint JSON, mais un export CSV
//! destiné à un rapport se filtre naturellement par plage de dates — parsé
//! manuellement en `Option<NaiveDate>` (comme `marketplace.rs::date_filter`)
//! plutôt que typé sur la query struct, pour renvoyer `422 validation_error`
//! plutôt que le rejet 400 générique d'axum sur une valeur non parsable.
//!
//! Pas de dépendance au crate `csv` : le nombre de colonnes est fixe et
//! connu, une génération manuelle avec échappement RFC 4180 minimal suffit.

use axum::extract::{Query, State};
use axum::http::{header, HeaderValue, StatusCode};
use axum::response::{IntoResponse, Response};
use chrono::NaiveDate;
use serde::Deserialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProAdminClaims},
    cabinet_quotes::VALID_QUOTE_STATUSES,
    AppState,
};

#[derive(Deserialize)]
pub struct ExportCabinetQuotesQuery {
    pub status: Option<String>,
    pub date_from: Option<String>,
    pub date_to: Option<String>,
}

/// `GET /v1/cabinet/quotes/export.csv` — export CSV des devis du cabinet.
///
/// Rôle `admin` uniquement (`ProAdminClaims`) — tout autre rôle pro → `403`,
/// token patient/pharma → `403`, pas de token → `401`.
/// `cabinet_id` extrait du JWT, RLS scopée via `app.current_cabinet_id`.
/// `?status=` doit être une valeur de `VALID_QUOTE_STATUSES` → `400
/// invalid_status_filter` sinon (même contrat que `GET /v1/cabinet/quotes`).
/// `?date_from=`/`?date_to=` (format `YYYY-MM-DD`, bornes inclusives sur
/// `created_at`) → `422 validation_error` si non parsable.
/// Colonnes : `id,patient_id,patient_name,status,total_amount_cents,created_at`.
/// Réponse `200 Content-Type: text/csv; charset=utf-8`, tri `created_at DESC`.
pub async fn export_cabinet_quotes_csv(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Query(params): Query<ExportCabinetQuotesQuery>,
) -> Result<Response, AppError> {
    if let Some(ref status) = params.status {
        if !VALID_QUOTE_STATUSES.contains(&status.as_str()) {
            return Err(AppError::InvalidQuoteStatusFilter);
        }
    }
    let date_from: Option<NaiveDate> = params
        .date_from
        .as_deref()
        .map(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let date_to: Option<NaiveDate> = params
        .date_to
        .as_deref()
        .map(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT q.id, q.patient_id, \
                trim(concat(p.first_name, ' ', p.last_name)) AS patient_name, \
                q.status, (q.total_amount * 100)::bigint AS amount_cents, \
                q.created_at \
         FROM quote q \
         LEFT JOIN patient p ON p.id = q.patient_id \
         WHERE q.cabinet_id = $1 \
           AND ($2::text IS NULL OR q.status = $2) \
           AND ($3::date IS NULL OR q.created_at::date >= $3) \
           AND ($4::date IS NULL OR q.created_at::date <= $4) \
         ORDER BY q.created_at DESC",
    )
    .bind(claims.cabinet_id)
    .bind(&params.status)
    .bind(date_from)
    .bind(date_to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut csv = String::from("id,patient_id,patient_name,status,total_amount_cents,created_at\n");
    for row in &rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let patient_id: Option<Uuid> = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
        let patient_name: Option<String> = row
            .try_get("patient_name")
            .map_err(|_| AppError::Internal)?;
        let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
        let amount_cents: i64 = row
            .try_get("amount_cents")
            .map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        csv.push_str(&format!(
            "{},{},{},{},{},{}\n",
            id,
            patient_id.map(|p| p.to_string()).unwrap_or_default(),
            csv_escape(patient_name.as_deref().unwrap_or("")),
            status,
            amount_cents,
            created_at.to_rfc3339(),
        ));
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        count = rows.len(),
        "cabinet quotes exported to csv"
    );

    Ok((
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            HeaderValue::from_static("text/csv; charset=utf-8"),
        )],
        csv,
    )
        .into_response())
}

/// Échappement RFC 4180 minimal : un champ contenant une virgule, un
/// guillemet ou un saut de ligne est entouré de guillemets, les guillemets
/// internes doublés. `patient_name` est la seule colonne à risque (nom/prénom
/// libres) ; les autres colonnes sont des UUID/enum/nombre/date ISO.
fn csv_escape(field: &str) -> String {
    if field.contains(',') || field.contains('"') || field.contains('\n') {
        format!("\"{}\"", field.replace('"', "\"\""))
    } else {
        field.to_string()
    }
}
