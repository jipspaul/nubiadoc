//! Handler `POST /v1/auth/login`.

use argon2::{
    password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use axum::extract::{ConnectInfo, Json, State};
use axum::http::HeaderMap;
use axum_client_ip::{SecureClientIp, SecureClientIpSource};
use jsonwebtoken::{encode, EncodingKey, Header};
use serde::Deserialize;
use sqlx::Row;
use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::AppState;

use super::{AppError, LoginResponse, PatientClaims, ProClaims, ProRegisterClaims};

const RATE_WINDOW: Duration = Duration::from_secs(300);

const IP_RATE_WINDOW: Duration = Duration::from_secs(60);
const IP_RATE_MAX_ATTEMPTS: u32 = 5;

static LOGIN_IP_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn is_ip_rate_limited(ip: &str) -> bool {
    let mut map = LOGIN_IP_RATE.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();
    let entry = map.entry(ip.to_string()).or_insert((0, now));
    if now.duration_since(entry.1) >= IP_RATE_WINDOW {
        *entry = (1, now);
        false
    } else {
        entry.0 += 1;
        entry.0 > IP_RATE_MAX_ATTEMPTS
    }
}

/// Plafond de tentatives par email et par fenêtre. Surchargé via
/// `LOGIN_RATE_MAX_ATTEMPTS` (dev/E2E : les flows Playwright se reconnectent
/// des dizaines de fois avec le même compte seed). Défaut prod : 10.
static RATE_MAX_ATTEMPTS: LazyLock<u32> = LazyLock::new(|| {
    std::env::var("LOGIN_RATE_MAX_ATTEMPTS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(10)
});

static LOGIN_RATE: LazyLock<Mutex<HashMap<String, (u32, Instant)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Hash-leurre calculé une seule fois par process (#3813) : un email inconnu
/// exécute quand même un `verify_password` contre CE hash avant de renvoyer
/// `Unauthenticated`, pour que le coût CPU argon2 (coûteux, seul poste de
/// latence mesurable ici) soit identique au chemin « email connu, mauvais
/// mot de passe » — sinon le temps de réponse fuit l'existence du compte
/// (canal auxiliaire, même classe que #3785).
static DECOY_PASSWORD_HASH: LazyLock<String> = LazyLock::new(|| {
    let salt = SaltString::from_b64("ZGVjb3lzYWx0Q29uc3RhbnQ").expect("salt b64 valide");
    Argon2::default()
        .hash_password(b"decoy-constant-time-password", &salt)
        .expect("le hash-leurre doit être calculable")
        .to_string()
});

fn is_rate_limited(email: &str) -> bool {
    let mut map = LOGIN_RATE.lock().unwrap_or_else(|e| e.into_inner());
    let now = Instant::now();
    let entry = map.entry(email.to_lowercase()).or_insert((0, now));
    if now.duration_since(entry.1) >= RATE_WINDOW {
        *entry = (1, now);
        false
    } else {
        entry.0 += 1;
        entry.0 > *RATE_MAX_ATTEMPTS
    }
}

/// Corps de la requête `POST /v1/auth/login`.
#[derive(Deserialize)]
pub struct LoginBody {
    email: String,
    password: String,
    mfa_code: Option<String>,
}

/// `POST /v1/auth/login` — authentifie un patient ou un pro, émet access + refresh tokens.
///
/// Réponse neutre sur credentials incorrects (anti-énumération §1.8).
/// Si le compte pro a `totp_enabled = true` et qu'aucun `mfa_code` n'est fourni → `401 mfa_required`.
pub async fn login(
    State(state): State<AppState>,
    connect_info: Option<ConnectInfo<SocketAddr>>,
    headers: HeaderMap,
    Json(body): Json<LoginBody>,
) -> Result<Json<LoginResponse>, AppError> {
    // Derrière Caddy, l'IP de connexion TCP (`ConnectInfo`) est toujours celle
    // du reverse-proxy, identique pour tout appelant externe : un bucket par
    // peer TCP verrouille alors la plateforme entière (#3849). Caddy pose
    // `X-Forwarded-For` en y ajoutant l'IP réelle du client comme dernière
    // entrée (non falsifiable par le client, qui ne contrôle que les entrées
    // précédentes) ; on la préfère, avec repli sur le peer TCP quand l'en-tête
    // est absent (appels internes/tests hors Caddy).
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

    let mut auth_tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_login_email', $1, true)")
        .bind(&body.email)
        .execute(&mut *auth_tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, password_hash, kind, totp_enabled, totp_secret \
         FROM app_user WHERE email = $1",
    )
    .bind(&body.email)
    .fetch_optional(&mut *auth_tx)
    .await
    .map_err(|_| AppError::Internal)?;

    auth_tx.rollback().await.map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        // #3813 : verify-leurre à coût CPU équivalent (cf. DECOY_PASSWORD_HASH)
        // — un email inconnu ne doit pas répondre plus vite qu'un email connu.
        let decoy = PasswordHash::new(&DECOY_PASSWORD_HASH).map_err(|_| AppError::Internal)?;
        let _ = Argon2::default().verify_password(body.password.as_bytes(), &decoy);
        return Err(AppError::Unauthenticated);
    };

    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let password_hash: String = row
        .try_get("password_hash")
        .map_err(|_| AppError::Internal)?;
    let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let totp_enabled: bool = row
        .try_get("totp_enabled")
        .map_err(|_| AppError::Internal)?;
    let totp_secret: Option<String> = row.try_get("totp_secret").map_err(|_| AppError::Internal)?;

    // Un hash mal formé en base (ex. comptes seed 'SEED_PLACEHOLDER') ne doit
    // pas fuiter d'information : on le traite comme un échec d'auth (401 neutre),
    // exactement comme un mot de passe faux, et non comme une erreur 500.
    let parsed_hash = PasswordHash::new(&password_hash).map_err(|_| AppError::Unauthenticated)?;
    Argon2::default()
        .verify_password(body.password.as_bytes(), &parsed_hash)
        .map_err(|_| AppError::Unauthenticated)?;

    if kind == "pro" && totp_enabled {
        match &body.mfa_code {
            None => return Err(AppError::MfaRequired),
            Some(code) => {
                let secret = totp_secret.ok_or(AppError::Internal)?;
                let secret_bytes = Secret::Encoded(secret)
                    .to_bytes()
                    .map_err(|_| AppError::Unauthenticated)?;
                let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret_bytes)
                    .map_err(|_| AppError::Unauthenticated)?;
                if !totp.check_current(code).map_err(|_| AppError::Internal)? {
                    return Err(AppError::Unauthenticated);
                }
            }
        }
    }

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let mut context_required: Option<bool> = None;
    let access_token = if kind == "patient" {
        // patient_account a FORCE RLS avec account_auth_select. La policy
        // utilise un GUC dédié (app.current_login_user_id) introduit par la
        // migration 0069, posé UNIQUEMENT dans cette transaction de login.
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_login_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;

        let account_id: Uuid = acct_row
            .map(|r| r.try_get("id"))
            .transpose()
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;

        encode(
            &Header::default(),
            &PatientClaims {
                sub: user_id,
                kind: "patient".to_string(),
                account_id,
                exp,
            },
            &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
        )
        .map_err(|_| AppError::Internal)?
    } else {
        // Résoudre tous les memberships actifs via user_all_memberships() (SECURITY DEFINER,
        // migration 0089). Contexte unique : JWT porte cabinet_id+role+secretariat_id?.
        // Multi-appartenance : JWT nu (ProClaims) + context_required:true.
        let mut tx2 = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx2)
            .await
            .map_err(|_| AppError::Internal)?;
        let memberships =
            sqlx::query("SELECT cabinet_id, role, secretariat_id FROM user_all_memberships($1)")
                .bind(user_id)
                .fetch_all(&mut *tx2)
                .await
                .map_err(|_| AppError::Internal)?;
        tx2.commit().await.map_err(|_| AppError::Internal)?;

        if memberships.len() == 1 {
            let r = &memberships[0];
            let cabinet_id: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
            let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
            let secretariat_id: Option<Uuid> = r
                .try_get("secretariat_id")
                .map_err(|_| AppError::Internal)?;
            encode(
                &Header::default(),
                &ProRegisterClaims {
                    sub: user_id,
                    kind: "pro".to_string(),
                    cabinet_id,
                    role,
                    secretariat_id,
                    exp,
                },
                &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
            )
            .map_err(|_| AppError::Internal)?
        } else {
            // 0 memberships (no cabinet yet) or multi-membership: emit naked token.
            if memberships.len() > 1 {
                context_required = Some(true);
            }
            encode(
                &Header::default(),
                &ProClaims {
                    sub: user_id,
                    kind: "pro".to_string(),
                    exp,
                },
                &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
            )
            .map_err(|_| AppError::Internal)?
        }
    };

    let raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(LoginResponse {
        access_token,
        refresh_token: raw_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
        context_required,
    }))
}
