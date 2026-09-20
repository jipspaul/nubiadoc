//! Reprise de données (DP-F14.a #7179) : `POST /v1/cabinet/imports`
//! (upload), `POST …/:id/dry-run`, `POST …/:id/run`, `GET …/:id`.
//!
//! Quoi : un job `data_import_job` (migration 0168 + 0268) porte le fichier
//! source chiffré, son `kind` (parseur), et le rapport ligne à ligne.
//! Pipeline en 3 temps : upload (parse de validation, aucune écriture
//! métier) → dry-run (rapport à blanc, transaction annulée) → run (écriture
//! idempotente). Rôle secrétariat+ (`secretary`, `practitioner`, `admin` —
//! #7465 : livré dans app_secretariat, la restriction `admin` strict
//! rendait la feature inutilisable par son propre public).
//!
//! Architecture : `source.rs` (trait `ImportSource` + lignes normalisées),
//! `csv.rs` (1er parseur), `pipeline.rs` (application tenant + rapport).
//! Un nouveau format = un module parseur + une branche dans `source_for`.
//!
//! Modes d'échec : fichier inexploitable → job créé en `failed` avec le
//! motif dans `report` (trace de la tentative), `201` ; `run` concurrent →
//! `409 invalid_status` ; KMS absent/mal formé → `503 kms_not_configured`
//! logué (#6980, cf. `crate::kms_env` — le fichier ne peut être ni stocké
//! ni relu en clair : il peut contenir des INS).

pub mod csv;
pub mod pipeline;
pub mod source;

use axum::{
    extract::{Multipart, Path, State},
    http::StatusCode,
    Json,
};
use core_crypto::{decrypt_column, encrypt_column, LocalKeyManager};
use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    AppState,
};
use pipeline::Summary;
use source::{source_for, ImportKind, ParsedLine};

/// Taille max du fichier de reprise (10 Mo ≈ 50 000 lignes CSV).
pub const MAX_IMPORT_SIZE: usize = 10 * 1024 * 1024;

/// Clé KMS partagée (`crate::kms_env`) : absente/mal formée → `503
/// kms_not_configured` logué, jamais un 500 muet (#6980).
fn key_manager_from_env() -> Result<LocalKeyManager, AppError> {
    crate::kms_env::key_manager_from_env().map_err(|e| {
        tracing::error!(error = %e, "data_import: clé KMS inexploitable");
        AppError::KmsNotConfigured
    })
}

/// Vue d'un job telle que rendue par les 4 endpoints.
#[derive(Serialize)]
pub struct ImportJobView {
    pub id: Uuid,
    pub kind: String,
    pub source_system: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file_name: Option<String>,
    pub status: String,
    pub total_count: i32,
    pub imported_count: i32,
    pub skipped_count: i32,
    pub error_count: i32,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub started_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub finished_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dry_run_at: Option<String>,
    pub created_at: String,
    pub report: serde_json::Value,
}

fn report_json(mode: &str, summary: &Summary) -> serde_json::Value {
    serde_json::json!({
        "mode": mode,
        "total": summary.total,
        "created": summary.created,
        "updated": summary.updated,
        "unchanged": summary.unchanged,
        "errors": summary.errors,
        "lines": summary.report,
    })
}

async fn begin_tenant_tx(
    state: &AppState,
    cabinet_id: Uuid,
) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    Ok(tx)
}

fn ts(v: Option<chrono::DateTime<chrono::Utc>>) -> Option<String> {
    v.map(|d| d.to_rfc3339())
}

async fn fetch_job(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    cabinet_id: Uuid,
    job_id: Uuid,
) -> Result<ImportJobView, AppError> {
    let row = sqlx::query(
        "SELECT id, kind, source_system, file_name, status, total_count, imported_count, \
                skipped_count, error_count, started_at, finished_at, dry_run_at, created_at, report \
         FROM data_import_job WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(job_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    macro_rules! col {
        ($name:literal) => {
            row.try_get($name).map_err(|_| AppError::Internal)?
        };
    }
    Ok(ImportJobView {
        id: col!("id"),
        kind: col!("kind"),
        source_system: col!("source_system"),
        file_name: col!("file_name"),
        status: col!("status"),
        total_count: col!("total_count"),
        imported_count: col!("imported_count"),
        skipped_count: col!("skipped_count"),
        error_count: col!("error_count"),
        started_at: ts(col!("started_at")),
        finished_at: ts(col!("finished_at")),
        dry_run_at: ts(col!("dry_run_at")),
        created_at: row
            .try_get::<chrono::DateTime<chrono::Utc>, _>("created_at")
            .map_err(|_| AppError::Internal)?
            .to_rfc3339(),
        report: col!("report"),
    })
}

/// Relit et déchiffre le fichier d'un job, puis le re-parse (le parseur
/// est déterministe : même fichier = mêmes lignes qu'à l'upload).
async fn load_lines(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    cabinet_id: Uuid,
    job_id: Uuid,
    key_manager: &LocalKeyManager,
) -> Result<(ImportKind, String, Vec<ParsedLine>), AppError> {
    let row = sqlx::query(
        "SELECT kind, status, payload_ciphertext, payload_key_ref \
         FROM data_import_job WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(job_id)
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let kind_raw: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let kind = ImportKind::parse(&kind_raw).ok_or(AppError::Internal)?;
    let ciphertext: Option<Vec<u8>> = row
        .try_get("payload_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let key_ref: Option<String> = row
        .try_get("payload_key_ref")
        .map_err(|_| AppError::Internal)?;
    let (Some(ciphertext), Some(key_ref)) = (ciphertext, key_ref) else {
        // Job de suivi legacy (0168) sans fichier : rien à rejouer.
        return Err(AppError::InvalidStatus);
    };
    let plain = decrypt_column(&ciphertext, key_manager, &cabinet_id.to_string(), &key_ref)
        .await
        .map_err(|_| AppError::Internal)?;
    let lines = source_for(kind)
        .parse(&plain)
        .map_err(|_| AppError::InvalidStatus)?;
    Ok((kind, status, lines))
}

/// `POST /v1/cabinet/imports` — multipart : `kind` (`csv_patients` |
/// `csv_appointments`), `file` (≤ 10 Mo), `source_system?` (libre, ex.
/// « Doctolib », défaut `csv`). Le fichier est parsé pour validation (aucune
/// écriture patient/RDV) et stocké chiffré. → `201` vue du job (`pending`,
/// ou `failed` si le fichier est inexploitable, motif dans `report`).
pub(crate) async fn upload_import(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<ImportJobView>), AppError> {
    let mut kind_raw: Option<String> = None;
    let mut source_system: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;
    let mut file_name: Option<String> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| AppError::ValidationError)?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "kind" => kind_raw = Some(field.text().await.map_err(|_| AppError::ValidationError)?),
            "source_system" => {
                source_system = Some(field.text().await.map_err(|_| AppError::ValidationError)?)
            }
            "file" => {
                file_name = field.file_name().map(|s| s.chars().take(200).collect());
                let bytes = field.bytes().await.map_err(|_| AppError::ValidationError)?;
                if bytes.len() > MAX_IMPORT_SIZE {
                    return Err(AppError::ValidationError);
                }
                file_bytes = Some(bytes.to_vec());
            }
            _ => {}
        }
    }

    let kind = ImportKind::parse(&kind_raw.ok_or(AppError::ValidationError)?)
        .ok_or(AppError::ValidationError)?;
    let file_bytes = file_bytes.ok_or(AppError::ValidationError)?;
    if file_bytes.is_empty() {
        return Err(AppError::ValidationError);
    }
    let source_system = source_system
        .map(|s| s.trim().chars().take(80).collect::<String>())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "csv".to_string());

    let key_manager = key_manager_from_env()?;
    let encrypted = encrypt_column(&file_bytes, &key_manager, &claims.cabinet_id.to_string())
        .await
        .map_err(|_| AppError::Internal)?;

    // Validation de forme à l'upload : erreur fichier → job `failed` (trace),
    // erreurs de lignes → comptées mais rien n'est écrit avant le run.
    let (status, total, report) = match source_for(kind).parse(&file_bytes) {
        Ok(lines) => {
            let invalid = lines.iter().filter(|l| l.record.is_err()).count();
            let preview: Vec<serde_json::Value> = lines
                .iter()
                .filter_map(|l| {
                    l.record.as_ref().err().map(|msg| {
                        serde_json::json!({
                            "line": l.line,
                            "external_ref": l.external_ref,
                            "action": "error",
                            "message": msg,
                        })
                    })
                })
                .collect();
            (
                "pending",
                lines.len(),
                serde_json::json!({
                    "mode": "upload",
                    "total": lines.len(),
                    "errors": invalid,
                    "lines": preview,
                }),
            )
        }
        Err(e) => (
            "failed",
            0,
            serde_json::json!({
                "mode": "upload",
                "total": 0,
                "errors": 1,
                "lines": [{ "line": 1, "action": "error", "message": e.to_string() }],
            }),
        ),
    };

    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    let row = sqlx::query(
        "INSERT INTO data_import_job \
           (cabinet_id, source_system, kind, file_name, payload_ciphertext, payload_key_ref, \
            status, total_count, report, created_by) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(&source_system)
    .bind(kind.as_str())
    .bind(&file_name)
    .bind(&encrypted.ciphertext)
    .bind(&encrypted.key_ref)
    .bind(status)
    .bind(total as i32)
    .bind(&report)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let job_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'data_import_upload', 'data_import_job', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(job_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let view = fetch_job(&mut tx, claims.cabinet_id, job_id).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;
    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        job_id = %job_id,
        kind = kind.as_str(),
        total,
        "data import uploaded"
    );
    Ok((StatusCode::CREATED, Json(view)))
}

/// `GET /v1/cabinet/imports/:id` — statut, compteurs, rapport. Absent ou
/// autre cabinet → `404`.
pub(crate) async fn get_import(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(job_id): Path<Uuid>,
) -> Result<Json<ImportJobView>, AppError> {
    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    let view = fetch_job(&mut tx, claims.cabinet_id, job_id).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(view))
}

/// `POST /v1/cabinet/imports/:id/dry-run` — analyse à blanc : même
/// pipeline que le run, transaction annulée. Pose `dry_run_at` + `report`
/// (`mode: "dry_run"`), ne change ni le statut ni les compteurs du run.
/// `409 invalid_status` si un run est en cours ou si le fichier est
/// inexploitable.
pub(crate) async fn dry_run_import(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(job_id): Path<Uuid>,
) -> Result<Json<ImportJobView>, AppError> {
    let key_manager = key_manager_from_env()?;
    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    let (_, status, lines) = load_lines(&mut tx, claims.cabinet_id, job_id, &key_manager).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;
    if status == "running" {
        return Err(AppError::InvalidStatus);
    }

    let created_by_secretariat_id = (claims.role == "secretary")
        .then_some(claims.secretariat_id)
        .flatten();
    let summary = pipeline::apply(
        &state.db,
        claims.cabinet_id,
        &lines,
        true,
        &key_manager,
        created_by_secretariat_id,
    )
    .await?;

    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    sqlx::query(
        "UPDATE data_import_job SET dry_run_at = now(), report = $1, total_count = $2 \
         WHERE id = $3 AND cabinet_id = $4",
    )
    .bind(report_json("dry_run", &summary))
    .bind(summary.total as i32)
    .bind(job_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let view = fetch_job(&mut tx, claims.cabinet_id, job_id).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;
    Ok(Json(view))
}

/// `POST /v1/cabinet/imports/:id/run` — import effectif, idempotent
/// (re-jouable : clé externe, sinon nom + prénom + naissance). Verrou
/// applicatif : `pending|completed|failed` → `running` ; un second run
/// concurrent reçoit `409 invalid_status`. Fin : `completed` (même avec des
/// erreurs de lignes — elles sont dans le rapport) ou `failed` (erreur
/// technique, rien n'est écrit).
pub(crate) async fn run_import(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(job_id): Path<Uuid>,
) -> Result<Json<ImportJobView>, AppError> {
    let key_manager = key_manager_from_env()?;
    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    let (_, _, lines) = load_lines(&mut tx, claims.cabinet_id, job_id, &key_manager).await?;
    let locked = sqlx::query(
        "UPDATE data_import_job \
         SET status = 'running', started_at = now(), finished_at = NULL \
         WHERE id = $1 AND cabinet_id = $2 AND status <> 'running'",
    )
    .bind(job_id)
    .bind(claims.cabinet_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if locked.rows_affected() == 0 {
        return Err(AppError::InvalidStatus);
    }
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let created_by_secretariat_id = (claims.role == "secretary")
        .then_some(claims.secretariat_id)
        .flatten();
    let outcome = pipeline::apply(
        &state.db,
        claims.cabinet_id,
        &lines,
        false,
        &key_manager,
        created_by_secretariat_id,
    )
    .await;

    let mut tx = begin_tenant_tx(&state, claims.cabinet_id).await?;
    match &outcome {
        Ok(summary) => {
            sqlx::query(
                "UPDATE data_import_job \
                 SET status = 'completed', finished_at = now(), report = $1, total_count = $2, \
                     imported_count = $3, skipped_count = $4, error_count = $5 \
                 WHERE id = $6 AND cabinet_id = $7",
            )
            .bind(report_json("run", summary))
            .bind(summary.total as i32)
            .bind((summary.created + summary.updated) as i32)
            .bind(summary.unchanged as i32)
            .bind(summary.errors as i32)
            .bind(job_id)
            .bind(claims.cabinet_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
        Err(_) => {
            sqlx::query(
                "UPDATE data_import_job SET status = 'failed', finished_at = now() \
                 WHERE id = $1 AND cabinet_id = $2",
            )
            .bind(job_id)
            .bind(claims.cabinet_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
    }
    sqlx::query(
        "INSERT INTO audit_log (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'data_import_run', 'data_import_job', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(job_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let view = fetch_job(&mut tx, claims.cabinet_id, job_id).await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    let summary = outcome?;
    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        job_id = %job_id,
        created = summary.created,
        updated = summary.updated,
        unchanged = summary.unchanged,
        errors = summary.errors,
        "data import run completed"
    );
    Ok(Json(view))
}
