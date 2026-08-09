//! Handlers traçabilité stérilisation (#4138), sur `sterilization_cycle`/
//! `sterilized_pouch` (migration 0190, #4137) :
//! - `GET/POST /v1/cabinet/sterilization-cycles`
//! - `GET/POST /v1/cabinet/sterilization-cycles/:id/pouches` (#4354 : le GET
//!   manquait — la traçabilité était write-only, jamais relisible)
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : la
//! traçabilité de stérilisation est une tâche opérationnelle du cabinet,
//! pas une décision clinique — même pattern que
//! `cabinet_cash_register.rs`, pas de garde relation-de-soin.

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

const VALID_TEST_KINDS: [&str; 2] = ["bowie_dick", "helix"];
const VALID_STATUSES: [&str; 2] = ["conforme", "non_conforme"];

// ── GET/POST /v1/cabinet/sterilization-cycles ────────────────────────────────

/// Un cycle de stérilisation.
#[derive(Serialize)]
pub struct SterilizationCycleDto {
    pub id: Uuid,
    pub autoclave_ref: String,
    pub cycle_number: i32,
    pub started_at: String,
    pub test_kind: String,
    pub test_result: String,
    pub status: String,
}

/// `GET /v1/cabinet/sterilization-cycles` — liste les cycles du cabinet,
/// du plus récent au plus ancien.
pub async fn list_sterilization_cycles(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<SterilizationCycleDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, autoclave_ref, cycle_number, started_at, test_kind, test_result, status \
         FROM sterilization_cycle \
         WHERE cabinet_id = $1 \
         ORDER BY started_at DESC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut cycles = Vec::with_capacity(rows.len());
    for row in &rows {
        let started_at: chrono::DateTime<chrono::Utc> =
            row.try_get("started_at").map_err(|_| AppError::Internal)?;
        cycles.push(SterilizationCycleDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            autoclave_ref: row
                .try_get("autoclave_ref")
                .map_err(|_| AppError::Internal)?,
            cycle_number: row
                .try_get("cycle_number")
                .map_err(|_| AppError::Internal)?,
            started_at: started_at.to_rfc3339(),
            test_kind: row.try_get("test_kind").map_err(|_| AppError::Internal)?,
            test_result: row.try_get("test_result").map_err(|_| AppError::Internal)?,
            status: row.try_get("status").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(cycles))
}

/// Body de `POST /v1/cabinet/sterilization-cycles`.
#[derive(Deserialize)]
pub struct CreateSterilizationCycleBody {
    pub autoclave_ref: String,
    pub cycle_number: i32,
    pub test_kind: String,
    pub test_result: String,
    pub status: String,
}

/// Réponse de `POST /v1/cabinet/sterilization-cycles`.
#[derive(Serialize)]
pub struct CreateSterilizationCycleResponse {
    pub cycle_id: Uuid,
}

/// `POST /v1/cabinet/sterilization-cycles` — enregistre un cycle
/// (conforme ou non — la traçabilité n'est jamais bloquante, un cycle
/// `non_conforme` doit pouvoir être tracé au même titre qu'un cycle
/// conforme, cf. #4138).
///
/// `autoclave_ref` non vide, `cycle_number > 0`, `test_result` non vide,
/// `test_kind` ∈ `VALID_TEST_KINDS`, `status` ∈ `VALID_STATUSES` → 422 sinon.
/// `(autoclave_ref, cycle_number)` déjà utilisé dans ce cabinet → `409
/// sterilization_cycle_number_already_used` (index unique `(cabinet_id,
/// autoclave_ref, cycle_number)`, migration 0202, #4489 — un cycle_number
/// pour un autoclave donné est un compteur physique unique, le registre de
/// traçabilité ne doit jamais contenir deux cycles homonymes).
pub async fn create_sterilization_cycle(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateSterilizationCycleBody>,
) -> Result<(StatusCode, Json<CreateSterilizationCycleResponse>), AppError> {
    if body.autoclave_ref.trim().is_empty()
        || body.cycle_number <= 0
        || body.test_result.trim().is_empty()
    {
        return Err(AppError::ValidationError);
    }
    if !VALID_TEST_KINDS.contains(&body.test_kind.as_str())
        || !VALID_STATUSES.contains(&body.status.as_str())
    {
        return Err(AppError::ValidationError);
    }
    // #4600 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(&body.autoclave_ref)?;
    crate::text_validation::reject_nul_byte(&body.test_result)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO sterilization_cycle \
         (cabinet_id, autoclave_ref, cycle_number, test_kind, test_result, status) \
         VALUES ($1, $2, $3, $4, $5, $6) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(body.autoclave_ref.trim())
    .bind(body.cycle_number)
    .bind(&body.test_kind)
    .bind(body.test_result.trim())
    .bind(&body.status)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::SterilizationCycleNumberAlreadyUsed
        }
        _ => AppError::Internal,
    })?;

    let cycle_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        cycle_id = %cycle_id,
        status = %body.status,
        "sterilization cycle created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateSterilizationCycleResponse { cycle_id }),
    ))
}

// ── POST /v1/cabinet/sterilization-cycles/:id/pouches ────────────────────────

/// Body de `POST /v1/cabinet/sterilization-cycles/:id/pouches`.
#[derive(Deserialize)]
pub struct AddPouchBody {
    pub code: String,
    pub consultation_act_id: Option<Uuid>,
}

/// Réponse de `POST /v1/cabinet/sterilization-cycles/:id/pouches`.
#[derive(Serialize)]
pub struct AddPouchResponse {
    pub pouch_id: Uuid,
}

/// `POST /v1/cabinet/sterilization-cycles/:id/pouches` — scan d'une
/// pochette (datamatrix/barcode), avec association optionnelle à l'acte
/// où elle a été utilisée.
///
/// Cycle inexistant/hors tenant → 404. `code` non vide → 422 sinon.
/// Reste possible quel que soit `sterilization_cycle.status` (traçabilité
/// non bloquante, cf. #4138 — un cycle non conforme doit pouvoir être
/// documenté, pas seulement les cycles réussis).
/// `consultation_act_id` (si fourni) doit exister dans ce cabinet → 404
/// sinon (FK composite (id, cabinet_id), migration 0190 — pré-vérifié pour
/// ne pas laisser remonter la contrainte en 500, cf. précédent
/// `prescriptions.rs`).
/// `code` déjà scanné dans ce cabinet → `409 pouch_code_already_used`
/// (index unique `(cabinet_id, code)`, migration 0191, #4139).
pub async fn add_sterilized_pouch(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(cycle_id): Path<Uuid>,
    Json(body): Json<AddPouchBody>,
) -> Result<(StatusCode, Json<AddPouchResponse>), AppError> {
    if body.code.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    // #4600/#4727 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(&body.code)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cycle_exists =
        sqlx::query("SELECT 1 FROM sterilization_cycle WHERE id = $1 AND cabinet_id = $2")
            .bind(cycle_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if cycle_exists.is_none() {
        return Err(AppError::NotFound);
    }

    if let Some(act_id) = body.consultation_act_id {
        let act_exists =
            sqlx::query("SELECT 1 FROM consultation_act WHERE id = $1 AND cabinet_id = $2")
                .bind(act_id)
                .bind(claims.cabinet_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        if act_exists.is_none() {
            return Err(AppError::NotFound);
        }
    }

    let row = sqlx::query(
        "INSERT INTO sterilized_pouch (cabinet_id, cycle_id, code, consultation_act_id) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(cycle_id)
    .bind(body.code.trim())
    .bind(body.consultation_act_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| match &e {
        sqlx::Error::Database(db) if db.code().as_deref() == Some("23505") => {
            AppError::PouchCodeAlreadyUsed
        }
        _ => AppError::Internal,
    })?;

    let pouch_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        cycle_id = %cycle_id,
        pouch_id = %pouch_id,
        "sterilized pouch added"
    );

    Ok((StatusCode::CREATED, Json(AddPouchResponse { pouch_id })))
}

// ── GET /v1/cabinet/sterilization-cycles/:id/pouches ─────────────────────────

/// Une pochette stérilisée scannée.
#[derive(Serialize)]
pub struct SterilizedPouchDto {
    pub id: Uuid,
    pub code: String,
    pub consultation_act_id: Option<Uuid>,
}

/// `GET /v1/cabinet/sterilization-cycles/:id/pouches` — liste les pochettes
/// scannées pour un cycle (#4354 : la donnée était write-only, aucun
/// endpoint ne la relisait, contrairement au but même du registre —
/// traçabilité lot ↔ patient ↔ acte, migration 0190).
///
/// Cycle inexistant/hors tenant → 404.
pub async fn list_sterilized_pouches(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(cycle_id): Path<Uuid>,
) -> Result<Json<Vec<SterilizedPouchDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cycle_exists =
        sqlx::query("SELECT 1 FROM sterilization_cycle WHERE id = $1 AND cabinet_id = $2")
            .bind(cycle_id)
            .bind(claims.cabinet_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if cycle_exists.is_none() {
        return Err(AppError::NotFound);
    }

    let rows = sqlx::query(
        "SELECT id, code, consultation_act_id FROM sterilized_pouch \
         WHERE cycle_id = $1 AND cabinet_id = $2 ORDER BY code",
    )
    .bind(cycle_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let pouches = rows
        .into_iter()
        .map(|row| {
            Ok(SterilizedPouchDto {
                id: row.try_get("id").map_err(|_| AppError::Internal)?,
                code: row.try_get("code").map_err(|_| AppError::Internal)?,
                consultation_act_id: row
                    .try_get("consultation_act_id")
                    .map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(pouches))
}
