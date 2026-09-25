//! Pointage d'équipe (DP-F27.b, #7144) — QR tournant (code renouvelé toutes
//! les 60 s) ou saisie manuelle autorisée, sur `time_clock_entry` (#7145,
//! migration 0300). Séparé de `staff.rs` pour rester sous le plafond de
//! taille par fichier (même choix que `appointments_checkin.rs` extrait de
//! `appointments.rs`).
//!
//! Le code affiché sur la borne (tablette d'accueil) est un TOTP (`totp-rs`,
//! déjà dépendance pour la MFA — cf. `auth/mfa_verify.rs`) dérivé du
//! `cabinet_id` par HMAC-SHA256 de `jwt_secret` (`hmac`/`sha2`, déjà
//! dépendances — cf. `local_storage_signer.rs`) : aucun secret persisté,
//! aucune nouvelle table/colonne pour ce fichier (l'issue est côté
//! `rust-agent`, la DB a été traitée par #7145). Le membre scanne ce code
//! avec son mobile pour badger — `POST .../in|out` avec `code` badge
//! toujours SOI-MÊME (`source = 'mobile'`), jamais un tiers : la borne ne
//! prouve que la présence physique, pas l'identité du porteur. Sans `code`,
//! la saisie est manuelle (`source = 'manual'`), réservée aux rôles
//! `MANUAL_ENTRY_ROLES` (correction/oubli par le secrétariat) — un
//! praticien ne peut pas se déclarer manuellement présent.

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    Json,
};
use chrono::{DateTime, Utc};
use hmac::{Hmac, Mac};
use serde::{Deserialize, Serialize};
use sha2::Sha256;
use sqlx::Row;
use totp_rs::{Algorithm, TOTP};
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    staff::{audit, parse_instant},
    AppState,
};

type HmacSha256 = Hmac<Sha256>;

const TOTP_STEP_SECS: u64 = 60;
const TOTP_DIGITS: usize = 6;
const TOTP_SKEW: u8 = 1;
const MANUAL_ENTRY_ROLES: [&str; 3] = ["secretary", "admin", "manager"];
/// Fenêtre de rattrapage pour une saisie/correction manuelle — même choix
/// que `cabinet_cash_register::MAX_PAST_DAYS` (#4393) : borne une date
/// passée sans bloquer une correction tardive plausible (secrétariat qui
/// rattrape un oubli de la semaine).
const MAX_PAST_DAYS: i64 = 31;

/// Un horodatage de correction manuelle doit être passé (ou présent) et pas
/// antérieur à `MAX_PAST_DAYS` — sinon la saisie manuelle pourrait fabriquer
/// une présence future ou une date aberrante.
fn validate_manual_timestamp(ts: DateTime<Utc>) -> Result<(), AppError> {
    let now = Utc::now();
    if ts > now || ts < now - chrono::Duration::days(MAX_PAST_DAYS) {
        return Err(AppError::ValidationError);
    }
    Ok(())
}

/// TOTP du cabinet : secret dérivé, jamais stocké — dérivable à nouveau à
/// chaque appel à partir de `jwt_secret` (jamais exposé au client) et
/// `cabinet_id` (public, dans le JWT pro).
fn cabinet_totp(jwt_secret: &str, cabinet_id: Uuid) -> Result<TOTP, AppError> {
    let mut mac =
        HmacSha256::new_from_slice(jwt_secret.as_bytes()).map_err(|_| AppError::Internal)?;
    mac.update(b"staff-time-clock-qr:");
    mac.update(cabinet_id.as_bytes());
    let secret = mac.finalize().into_bytes().to_vec();
    TOTP::new(
        Algorithm::SHA1,
        TOTP_DIGITS,
        TOTP_SKEW,
        TOTP_STEP_SECS,
        secret,
    )
    .map_err(|_| AppError::Internal)
}

/// Réponse de `GET /v1/cabinet/staff/time-clock/code`.
#[derive(Serialize)]
pub struct TimeClockCodeResponse {
    pub code: String,
    pub expires_in_seconds: u64,
}

/// `GET /v1/cabinet/staff/time-clock/code` — code courant à afficher sur la
/// borne (encodé en QR côté client — cette route renvoie le texte, pas une
/// image, même contrat que `appointments_checkin.rs::CheckinBody::qr_code`).
pub async fn time_clock_code(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<TimeClockCodeResponse>, AppError> {
    let totp = cabinet_totp(&state.jwt_secret, claims.cabinet_id)?;
    let code = totp.generate_current().map_err(|_| AppError::Internal)?;
    let expires_in_seconds = totp.ttl().map_err(|_| AppError::Internal)?;
    Ok(Json(TimeClockCodeResponse {
        code,
        expires_in_seconds,
    }))
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ClockBody {
    /// Ignoré si `code` est fourni (le pointage QR est toujours pour soi).
    pub user_id: Option<Uuid>,
    pub code: Option<String>,
    /// Horodatage de correction pour `clock_in` — saisie manuelle
    /// uniquement (`code` absent) : le badge QR/mobile fait toujours foi de
    /// l'instant présent, jamais d'un instant fourni par le client.
    pub clock_in: Option<String>,
    /// Idem pour `clock_out`.
    pub clock_out: Option<String>,
}

#[derive(Serialize)]
pub struct TimeClockEntryItem {
    pub id: Uuid,
    pub user_id: Uuid,
    pub clock_in: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub clock_out: Option<String>,
    pub source: String,
}

fn entry_row_to_item(row: &sqlx::postgres::PgRow) -> Result<TimeClockEntryItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
    let clock_in: DateTime<Utc> = row.try_get("clock_in").map_err(|_| AppError::Internal)?;
    let clock_out: Option<DateTime<Utc>> =
        row.try_get("clock_out").map_err(|_| AppError::Internal)?;
    let source: String = row.try_get("source").map_err(|_| AppError::Internal)?;
    Ok(TimeClockEntryItem {
        id,
        user_id,
        clock_in: clock_in.to_rfc3339(),
        clock_out: clock_out.map(|d| d.to_rfc3339()),
        source,
    })
}

/// Résout `(user_id cible, source)` à partir du corps de requête — commun à
/// `clock_in`/`clock_out`. `code` invalide/expiré → 422 ; saisie manuelle
/// hors `MANUAL_ENTRY_ROLES` → 403.
fn resolve_target(
    state: &AppState,
    claims: &ProSecretaryPlusClaims,
    body: &ClockBody,
) -> Result<(Uuid, &'static str), AppError> {
    if let Some(code) = &body.code {
        let totp = cabinet_totp(&state.jwt_secret, claims.cabinet_id)?;
        let is_valid = totp.check_current(code).map_err(|_| AppError::Internal)?;
        if !is_valid {
            return Err(AppError::ValidationError);
        }
        Ok((claims.sub, "mobile"))
    } else {
        if !MANUAL_ENTRY_ROLES.contains(&claims.role.as_str()) {
            return Err(AppError::Forbidden);
        }
        Ok((body.user_id.unwrap_or(claims.sub), "manual"))
    }
}

/// `POST /v1/cabinet/staff/time-clock/in` — badge une entrée. Un pointage
/// déjà ouvert (`clock_out IS NULL`) pour ce membre → `409 invalid_status`
/// (pas de double entrée sans sortie).
pub async fn clock_in(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<ClockBody>,
) -> Result<(StatusCode, Json<TimeClockEntryItem>), AppError> {
    let (target_user_id, source) = resolve_target(&state, &claims, &body)?;
    let clock_in = match &body.clock_in {
        Some(ts) if source == "manual" => {
            let ts = parse_instant(ts)?;
            validate_manual_timestamp(ts)?;
            Some(ts)
        }
        Some(_) => return Err(AppError::ValidationError),
        None => None,
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let member =
        sqlx::query("SELECT 1 FROM cabinet_membership WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(target_user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    if member.is_none() {
        return Err(AppError::NotFound);
    }

    let open = sqlx::query(
        "SELECT 1 FROM time_clock_entry WHERE cabinet_id = $1 AND user_id = $2 AND clock_out IS NULL",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if open.is_some() {
        return Err(AppError::InvalidStatus);
    }

    let row = sqlx::query(
        "INSERT INTO time_clock_entry (cabinet_id, user_id, clock_in, source) \
         VALUES ($1, $2, COALESCE($3, now()), $4) \
         RETURNING id, user_id, clock_in, clock_out, source",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .bind(clock_in)
    .bind(source)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = entry_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "clock_in",
        "time_clock_entry",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        actor_id = %claims.sub,
        user_id = %target_user_id,
        source = %source,
        "time clock in"
    );

    Ok((StatusCode::CREATED, Json(item)))
}

/// `POST /v1/cabinet/staff/time-clock/out` — clôture le pointage ouvert du
/// membre ciblé. Aucun pointage ouvert → 404.
pub async fn clock_out(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<ClockBody>,
) -> Result<Json<TimeClockEntryItem>, AppError> {
    let (target_user_id, source) = resolve_target(&state, &claims, &body)?;
    let clock_out = match &body.clock_out {
        Some(ts) if source == "manual" => {
            let ts = parse_instant(ts)?;
            validate_manual_timestamp(ts)?;
            Some(ts)
        }
        Some(_) => return Err(AppError::ValidationError),
        None => None,
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let open = sqlx::query(
        "SELECT id, clock_in FROM time_clock_entry \
         WHERE cabinet_id = $1 AND user_id = $2 AND clock_out IS NULL \
         ORDER BY clock_in DESC LIMIT 1",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let entry_id: Uuid = open.try_get("id").map_err(|_| AppError::Internal)?;
    if let Some(clock_out) = clock_out {
        let clock_in: DateTime<Utc> = open.try_get("clock_in").map_err(|_| AppError::Internal)?;
        if clock_out <= clock_in {
            return Err(AppError::ValidationError);
        }
    }

    let row = sqlx::query(
        "UPDATE time_clock_entry SET clock_out = COALESCE($1, now()) \
         WHERE id = $2 \
         RETURNING id, user_id, clock_in, clock_out, source",
    )
    .bind(clock_out)
    .bind(entry_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = entry_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "clock_out",
        "time_clock_entry",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        actor_id = %claims.sub,
        user_id = %target_user_id,
        "time clock out"
    );

    Ok(Json(item))
}

/// Query de `GET /v1/cabinet/staff/time-clock`.
#[derive(Deserialize)]
pub struct ListTimeClockQuery {
    pub user_id: Option<Uuid>,
    pub from: Option<String>,
    pub to: Option<String>,
}

/// `GET /v1/cabinet/staff/time-clock` — historique des pointages,
/// filtrable par membre et fenêtre `[from, to[` (bornes sur `clock_in`),
/// du plus récent au plus ancien.
pub async fn list_time_clock(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Query(params): Query<ListTimeClockQuery>,
) -> Result<Json<Vec<TimeClockEntryItem>>, AppError> {
    let from = params
        .from
        .as_deref()
        .map(|s| s.parse::<DateTime<Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    let to = params
        .to
        .as_deref()
        .map(|s| s.parse::<DateTime<Utc>>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, user_id, clock_in, clock_out, source FROM time_clock_entry \
         WHERE ($1::uuid IS NULL OR user_id = $1) \
           AND ($2::timestamptz IS NULL OR clock_in >= $2) \
           AND ($3::timestamptz IS NULL OR clock_in < $3) \
         ORDER BY clock_in DESC",
    )
    .bind(params.user_id)
    .bind(from)
    .bind(to)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    rows.iter()
        .map(entry_row_to_item)
        .collect::<Result<Vec<_>, _>>()
        .map(Json)
}

/// Corps de `PATCH /v1/cabinet/staff/time-clock/:id`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchTimeClockBody {
    pub clock_in: Option<String>,
    pub clock_out: Option<String>,
}

/// `PATCH /v1/cabinet/staff/time-clock/:id` — corrige un pointage existant
/// (oubli, erreur de borne QR/manuelle), réservé à `MANUAL_ENTRY_ROLES` —
/// même contrat de rôle que la saisie manuelle (`resolve_target`), même
/// symétrie que `staff::patch_shift` pour `staff_shift`.
pub async fn patch_time_clock_entry(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchTimeClockBody>,
) -> Result<Json<TimeClockEntryItem>, AppError> {
    if !MANUAL_ENTRY_ROLES.contains(&claims.role.as_str()) {
        return Err(AppError::Forbidden);
    }
    if body.clock_in.is_none() && body.clock_out.is_none() {
        return Err(AppError::ValidationError);
    }
    let new_clock_in = body.clock_in.as_deref().map(parse_instant).transpose()?;
    let new_clock_out = body.clock_out.as_deref().map(parse_instant).transpose()?;
    if let Some(ts) = new_clock_in {
        validate_manual_timestamp(ts)?;
    }
    if let Some(ts) = new_clock_out {
        validate_manual_timestamp(ts)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let existing = sqlx::query("SELECT clock_in, clock_out FROM time_clock_entry WHERE id = $1")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let cur_clock_in: DateTime<Utc> = existing
        .try_get("clock_in")
        .map_err(|_| AppError::Internal)?;
    let cur_clock_out: Option<DateTime<Utc>> = existing
        .try_get("clock_out")
        .map_err(|_| AppError::Internal)?;
    let effective_clock_in = new_clock_in.unwrap_or(cur_clock_in);
    let effective_clock_out = new_clock_out.or(cur_clock_out);
    if let Some(clock_out) = effective_clock_out {
        if clock_out <= effective_clock_in {
            return Err(AppError::ValidationError);
        }
    }

    let row = sqlx::query(
        "UPDATE time_clock_entry SET clock_in = $1, clock_out = $2 \
         WHERE id = $3 \
         RETURNING id, user_id, clock_in, clock_out, source",
    )
    .bind(effective_clock_in)
    .bind(effective_clock_out)
    .bind(id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let item = entry_row_to_item(&row)?;
    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "patch_time_clock_entry",
        "time_clock_entry",
        item.id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(Json(item))
}

/// `DELETE /v1/cabinet/staff/time-clock/:id` — supprime un pointage erroné,
/// réservé à `MANUAL_ENTRY_ROLES` (même garde que la correction).
pub async fn delete_time_clock_entry(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    if !MANUAL_ENTRY_ROLES.contains(&claims.role.as_str()) {
        return Err(AppError::Forbidden);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let deleted = sqlx::query("DELETE FROM time_clock_entry WHERE id = $1 RETURNING id")
        .bind(id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if deleted.is_none() {
        return Err(AppError::NotFound);
    }

    audit(
        &mut tx,
        claims.cabinet_id,
        claims.sub,
        &claims.role,
        "delete_time_clock_entry",
        "time_clock_entry",
        id,
    )
    .await?;
    tx.commit().await.map_err(|_| AppError::Internal)?;

    Ok(StatusCode::NO_CONTENT)
}
