//! Handler `POST /v1/auth/mfa/disable`.

use argon2::{
    password_hash::{PasswordHash, PasswordVerifier},
    Argon2,
};
use axum::extract::{ConnectInfo, Json, State};
use axum::http::HeaderMap;
use axum_client_ip::{SecureClientIp, SecureClientIpSource};
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use std::net::SocketAddr;
use uuid::Uuid;

use crate::AppState;

use super::login::{is_ip_rate_limited, is_rate_limited, DECOY_PASSWORD_HASH};
use super::AppError;

/// Corps de la requête `POST /v1/auth/mfa/disable`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MfaDisableBody {
    email: String,
    /// Mot de passe courant, redemandé pour confirmer la désactivation
    /// (un JWT volé/laissé ouvert ne doit pas suffire à couper le second
    /// facteur).
    password: String,
}

/// `POST /v1/auth/mfa/disable` — désactive la MFA TOTP du compte pro identifié par `email`.
///
/// Seule voie de désactivation hors reset de mot de passe complet (#7328) :
/// jusqu'ici, activer la MFA via `/mfa/verify` était irréversible sans passer
/// par `POST /v1/auth/password/reset`, qui exige l'accès à la boîte mail et
/// change le mot de passe au passage — inutilisable sur un compte partagé
/// (démo, cabinet).
///
/// Délibérément NON authentifié par JWT (#7342, suite de #7328) : exiger un
/// token pro fermait un cycle impossible à rompre — `login` refuse d'émettre
/// ce token tant que `totp_enabled = true`, et c'était justement le seul
/// moyen d'atteindre cette route. La preuve de possession est le mot de
/// passe courant (`MfaDisableBody.password`, vérifié ci-dessous via Argon2),
/// exactement comme `login` re-vérifie le mot de passe avant le second
/// facteur — le JWT n'apportait rien de plus ici. Mêmes gardes anti-abus
/// que `login` (rate-limit IP + email, leurre à coût CPU constant sur email
/// inconnu, réponse `401 unauthenticated` neutre) puisque c'est, comme
/// `login`, un endpoint anonyme qui vérifie un mot de passe.
pub async fn mfa_disable(
    State(state): State<AppState>,
    connect_info: Option<ConnectInfo<SocketAddr>>,
    headers: HeaderMap,
    Json(body): Json<MfaDisableBody>,
) -> Result<Json<Value>, AppError> {
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

    // app_user a FORCE RLS (migration 0045) : avant de connaître l'id de
    // l'utilisateur, seule la policy `user_login_select` (migration 0065,
    // même mécanisme que `auth::login`) autorise ce SELECT par email.
    let mut lookup_tx = state
        .db
        .begin()
        .await
        .map_err(|e| db_error(&e, "begin lookup"))?;
    sqlx::query("SELECT set_config('app.current_login_email', $1, true)")
        .bind(&body.email)
        .execute(&mut *lookup_tx)
        .await
        .map_err(|e| db_error(&e, "set_config app.current_login_email"))?;
    let row = sqlx::query("SELECT id, password_hash, totp_enabled FROM app_user WHERE email = $1")
        .bind(&body.email)
        .fetch_optional(&mut *lookup_tx)
        .await
        .map_err(|e| db_error(&e, "select app_user"))?;
    lookup_tx
        .rollback()
        .await
        .map_err(|e| db_error(&e, "rollback lookup"))?;

    let Some(row) = row else {
        // Même leurre à coût CPU constant que `login` (#3813) : un email
        // inconnu ne doit pas répondre plus vite qu'un email connu.
        let decoy = PasswordHash::new(&DECOY_PASSWORD_HASH).map_err(|_| AppError::Internal)?;
        let _ = Argon2::default().verify_password(body.password.as_bytes(), &decoy);
        return Err(AppError::Unauthenticated);
    };

    let user_id: Uuid = row.try_get("id").map_err(|e| db_error(&e, "read id"))?;
    let password_hash: Option<String> = row
        .try_get("password_hash")
        .map_err(|e| db_error(&e, "read password_hash"))?;
    let totp_enabled: bool = row
        .try_get("totp_enabled")
        .map_err(|e| db_error(&e, "read totp_enabled"))?;

    let Some(password_hash) = password_hash else {
        let decoy = PasswordHash::new(&DECOY_PASSWORD_HASH).map_err(|_| AppError::Internal)?;
        let _ = Argon2::default().verify_password(body.password.as_bytes(), &decoy);
        return Err(AppError::Unauthenticated);
    };

    let parsed_hash = PasswordHash::new(&password_hash).map_err(|_| AppError::Unauthenticated)?;
    Argon2::default()
        .verify_password(body.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthenticated)?;

    if !totp_enabled {
        return Err(AppError::InvalidStatus);
    }

    let mut tx = state.db.begin().await.map_err(|e| db_error(&e, "begin"))?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "set_config app.current_user_id"))?;

    sqlx::query("DELETE FROM mfa_enrollment WHERE app_user_id = $1 AND method = 'totp'")
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "delete mfa_enrollment"))?;
    sqlx::query("UPDATE app_user SET totp_enabled = false, updated_at = now() WHERE id = $1")
        .bind(user_id)
        .execute(&mut *tx)
        .await
        .map_err(|e| db_error(&e, "update app_user.totp_enabled"))?;
    tx.commit().await.map_err(|e| db_error(&e, "commit"))?;

    tracing::info!(user_id = %user_id, "mfa_disable: MFA TOTP désactivée");
    Ok(Json(json!({"message": "MFA désactivée."})))
}

/// Erreur SQL → `500` logué avec l'étape en cause (jamais un 500 muet).
fn db_error(e: &sqlx::Error, step: &'static str) -> AppError {
    tracing::error!(error = %e, step, "mfa_disable: échec base de données");
    AppError::Internal
}
