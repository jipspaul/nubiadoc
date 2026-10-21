//! Handler `POST /v1/auth/password/forgot`.

use axum::extract::{rejection::JsonRejection, ConnectInfo, State};
use axum::http::{HeaderMap, StatusCode};
use axum::Json;
use axum_client_ip::{SecureClientIp, SecureClientIpSource};
use serde::Deserialize;
use sqlx::Row;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};
use uuid::Uuid;

use crate::AppState;

use super::AppError;

/// #8273 : compteurs dédiés à `forgot_password`, distincts de ceux de
/// `auth::login`. Avant ce correctif, `is_ip_rate_limited`/`is_rate_limited`
/// étaient réutilisées directement depuis `auth::login` (#6800) : `/forgot`
/// dépensait alors le même budget que `/login`, au point qu'une poignée de
/// demandes de réinitialisation suffisait à bloquer la connexion légitime de
/// la victime (par IP) ou, pire, à verrouiller à distance n'importe quel
/// compte connu (par email, en prod où `RATE_MAX_ATTEMPTS` vaut 10).
const FORGOT_IP_RATE_WINDOW: Duration = Duration::from_secs(60);
const FORGOT_IP_RATE_MAX_ATTEMPTS: u32 = 5;

static FORGOT_IP_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_ip_rate_limited(ip: &str) -> bool {
    let mut map = FORGOT_IP_RATE.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();
    let entry = map.entry(ip.to_string()).or_insert((0, now));
    if now.duration_since(entry.1) >= FORGOT_IP_RATE_WINDOW {
        *entry = (1, now);
        false
    } else {
        entry.0 += 1;
        entry.0 > FORGOT_IP_RATE_MAX_ATTEMPTS
    }
}

const FORGOT_RATE_WINDOW: Duration = Duration::from_secs(300);
const FORGOT_RATE_MAX_ATTEMPTS: u32 = 10;

static FORGOT_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_rate_limited(email: &str) -> bool {
    let mut map = FORGOT_RATE.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();
    let entry = map.entry(email.to_lowercase()).or_insert((0, now));
    if now.duration_since(entry.1) >= FORGOT_RATE_WINDOW {
        *entry = (1, now);
        false
    } else {
        entry.0 += 1;
        entry.0 > FORGOT_RATE_MAX_ATTEMPTS
    }
}

/// Corps de la requête `POST /v1/auth/password/forgot`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ForgotPasswordBody {
    email: String,
}

/// `POST /v1/auth/password/forgot` — déclenche le reset de mot de passe.
///
/// Réponse toujours `204` que l'email existe ou non (anti-énumération §1.8).
/// Si l'email est connu, génère un token UUID, le stocke hashé (SHA-256 via pgcrypto)
/// avec une expiration d'une heure, puis notifie via le mailer.
///
/// #3785 : un email inconnu ne doit pas seulement renvoyer la MÊME réponse
/// qu'un email connu, mais faire le MÊME travail — sinon la latence (2e
/// transaction + UPDATE + mailer en plus pour un email connu) devient un
/// canal auxiliaire mesurable qui défait l'anti-énumération malgré le 204
/// constant. On exécute donc systématiquement la 2e transaction + l'UPDATE
/// (sur un id bidon si l'email est inconnu — 0 ligne affectée, même coût
/// d'index lookup) ; seul l'envoi mailer reste conditionnel au résultat réel.
///
/// Mêmes principes anti-abus que `login` (#6800) : rate-limit par IP (60 s)
/// puis par email (300 s), mais avec des compteurs **propres** à ce handler
/// (#8273) — sans ça, connaître l'email d'un tiers suffit à lui envoyer
/// autant d'e-mails de reset que voulu (harcèlement, noyage d'un envoi
/// légitime), ET ces mêmes demandes consomment le budget de `/auth/login`,
/// ce qui permet de bloquer la connexion (par IP) ou le compte (par email)
/// d'une victime sans jamais toucher à ses identifiants.
pub async fn forgot_password(
    State(state): State<AppState>,
    connect_info: Option<ConnectInfo<SocketAddr>>,
    headers: HeaderMap,
    body: Result<Json<ForgotPasswordBody>, JsonRejection>,
) -> Result<StatusCode, AppError> {
    let Json(body) = match body {
        Ok(b) => b,
        Err(_) => return Ok(StatusCode::UNPROCESSABLE_ENTITY),
    };

    let ip_key = SecureClientIp::from(
        &SecureClientIpSource::RightmostXForwardedFor,
        &headers,
        &Default::default(),
    )
    .map(|SecureClientIp(ip)| ip.to_string())
    .unwrap_or_else(|_| {
        connect_info
            .map(|ci| ci.0.ip().to_string())
            .unwrap_or_else(|| "unknown".to_string())
    });
    if is_ip_rate_limited(&ip_key) {
        return Err(AppError::TooManyRequests(60));
    }
    if is_rate_limited(&body.email) {
        return Err(AppError::TooManyRequests(300));
    }

    let token = Uuid::new_v4().to_string();

    // Pose app.current_login_email pour satisfaire user_login_select (migration 0065).
    let mut auth_tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(_) => return Ok(StatusCode::NO_CONTENT),
    };
    if sqlx::query("SELECT set_config('app.current_login_email', $1, true)")
        .bind(&body.email)
        .execute(&mut *auth_tx)
        .await
        .is_err()
    {
        return Ok(StatusCode::NO_CONTENT);
    }
    let user_row = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&body.email)
        .fetch_optional(&mut *auth_tx)
        .await;
    let _ = auth_tx.rollback().await;

    // Email inconnu → id bidon (ne matchera jamais de ligne réelle) plutôt
    // qu'un retour anticipé : la suite du handler s'exécute à l'identique.
    let (user_id, user_found) = match user_row {
        Ok(Some(r)) => match r.try_get::<Uuid, _>("id") {
            Ok(id) => (id, true),
            Err(_) => (Uuid::new_v4(), false),
        },
        _ => (Uuid::new_v4(), false),
    };

    let mut tx = match state.db.begin().await {
        Ok(tx) => tx,
        Err(_) => return Ok(StatusCode::NO_CONTENT),
    };

    if sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .is_err()
    {
        return Ok(StatusCode::NO_CONTENT);
    }

    let result = sqlx::query(
        r#"
        UPDATE app_user
        SET
            password_reset_token      = encode(digest($2, 'sha256'), 'hex'),
            password_reset_expires_at = now() + interval '1 hour'
        WHERE id = $1
        "#,
    )
    .bind(user_id)
    .bind(&token)
    .execute(&mut *tx)
    .await;

    match (result, tx.commit().await) {
        (Ok(outcome), Ok(())) if user_found && outcome.rows_affected() > 0 => {
            state.mailer.send_password_reset(&body.email, &token);
        }
        (Err(e), _) if user_found => {
            tracing::error!(error = ?e, "forgot_password: db update failed");
        }
        _ => {}
    }

    Ok(StatusCode::NO_CONTENT)
}
