//! Handler `GET /v1/cabinet/patients` — liste paginée des dossiers patients du cabinet.

use axum::extract::{Query, State};
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};

#[derive(Deserialize)]
pub struct ListPatientsQuery {
    /// Filtre textuel sur nom/prénom (ILIKE).
    pub q: Option<String>,
    /// `in_treatment` ou `to_review`.
    pub filter: Option<String>,
    pub limit: Option<i64>,
    pub cursor: Option<String>,
}

#[derive(Serialize)]
pub struct PatientItem {
    pub id: Uuid,
    pub first_name: String,
    pub last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub birth_date: Option<String>,
    pub created_at: String,
}

#[derive(Serialize)]
pub struct PageInfo {
    pub next_cursor: Option<String>,
    pub limit: i64,
}

#[derive(Serialize)]
pub struct ListPatientsResponse {
    pub data: Vec<PatientItem>,
    pub page: PageInfo,
}

fn encode_cursor(created_at: chrono::DateTime<chrono::Utc>, id: Uuid) -> String {
    format!("{}|{}", created_at.timestamp_micros(), id)
}

fn decode_cursor(s: &str) -> Option<(chrono::DateTime<chrono::Utc>, Uuid)> {
    let (micros_str, id_str) = s.split_once('|')?;
    let micros: i64 = micros_str.parse().ok()?;
    let dt = chrono::DateTime::from_timestamp_micros(micros)?;
    let id = Uuid::parse_str(id_str).ok()?;
    Some((dt, id))
}

/// `GET /v1/cabinet/patients` — liste paginée des dossiers patients du cabinet.
///
/// Token pro requis (secretary, practitioner, admin) — patient → 403.
/// `cabinet_id` extrait du JWT, jamais du query string (invariant tenancy).
/// RLS scopé via `app.current_cabinet_id`. Cloisonnement R.4127-72 : fiche admin uniquement
/// (données cliniques chiffrées non exposées ici).
/// Query : `q` (ILIKE nom/prénom), `filter=in_treatment|to_review`, `limit`, `cursor`.
pub async fn list_cabinet_patients(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListPatientsQuery>,
) -> Result<Json<ListPatientsResponse>, AppError> {
    let limit: i64 = params.limit.unwrap_or(20).clamp(1, 100);
    let fetch_limit = limit + 1;

    let cursor = params.cursor.as_deref().and_then(decode_cursor);
    let (cursor_at, cursor_id) = cursor
        .map(|(at, id)| (Some(at), Some(id)))
        .unwrap_or((None, None));

    // %q% search — ILIKE wildcards on user input are acceptable (parameterised query).
    let search_pattern = params.q.as_deref().map(|q| format!("%{}%", q));

    // Filtre statut : in_treatment = plan de traitement en cours ;
    // to_review = note clinique non validée (R.4127-72, praticien uniquement en pratique).
    let filter_clause = match params.filter.as_deref() {
        Some("in_treatment") => {
            " AND EXISTS (\
              SELECT 1 FROM treatment_plan tp2 \
              WHERE tp2.patient_id = p.id \
                AND tp2.status = 'in_progress' \
                AND tp2.deleted_at IS NULL\
            )"
        }
        Some("to_review") => {
            " AND EXISTS (\
              SELECT 1 FROM clinical_note cn \
              WHERE cn.patient_id = p.id \
                AND cn.validated_at IS NULL \
                AND cn.deleted_at IS NULL\
            )"
        }
        _ => "",
    };

    // $1 = fetch_limit, $2 = search_pattern (NULL → no filter), $3/$4 = cursor (NULL → no cursor).
    let sql = format!(
        "SELECT p.id, p.first_name, p.last_name, p.birth_date, p.created_at \
         FROM patient p \
         WHERE p.deleted_at IS NULL\
         {filter_clause} \
         AND ($2::text IS NULL OR p.first_name ILIKE $2 OR p.last_name ILIKE $2) \
         AND ($3::timestamptz IS NULL \
              OR p.created_at < $3 \
              OR (p.created_at = $3 AND p.id < $4)) \
         ORDER BY p.created_at DESC, p.id DESC \
         LIMIT $1"
    );

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(&sql)
        .bind(fetch_limit)
        .bind(search_pattern.as_deref())
        .bind(cursor_at)
        .bind(cursor_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let has_more = rows.len() > limit as usize;
    let visible = if has_more {
        &rows[..limit as usize]
    } else {
        &rows[..]
    };

    let mut data: Vec<PatientItem> = Vec::with_capacity(visible.len());
    let mut last_created_at: Option<chrono::DateTime<chrono::Utc>> = None;
    let mut last_id: Option<Uuid> = None;

    for row in visible {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
        let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
        let birth_date: Option<chrono::NaiveDate> =
            row.try_get("birth_date").map_err(|_| AppError::Internal)?;
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;

        last_created_at = Some(created_at);
        last_id = Some(id);

        data.push(PatientItem {
            id,
            first_name,
            last_name,
            birth_date: birth_date.map(|d| d.to_string()),
            created_at: created_at.to_rfc3339(),
        });
    }

    let next_cursor = if has_more {
        last_created_at
            .zip(last_id)
            .map(|(dt, id)| encode_cursor(dt, id))
    } else {
        None
    };

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        role = %claims.role,
        count = data.len(),
        has_more,
        "cabinet patients listed"
    );

    Ok(Json(ListPatientsResponse {
        data,
        page: PageInfo { next_cursor, limit },
    }))
}
