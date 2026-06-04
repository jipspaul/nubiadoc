//! Handlers d'authentification (routes publiques `/v1/auth/*`).

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use async_trait::async_trait;
use axum::{
    extract::{FromRequestParts, State},
    http::{request::Parts, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::AppState;

/// Corps de la requête `POST /v1/auth/login`.
#[derive(Deserialize)]
pub struct LoginBody {
    email: String,
    password: String,
    mfa_code: Option<String>,
}

/// Réponse de `POST /v1/auth/login`.
#[derive(Serialize)]
pub struct LoginResponse {
    access_token: String,
    refresh_token: String,
    token_type: String,
    expires_in: u64,
}

/// Corps de la requête `POST /v1/auth/register`.
#[derive(Deserialize)]
pub struct RegisterBody {
    email: String,
    password: String,
    accept_cgu: bool,
    cgu_version: String,
}

/// Sous-corps cabinet pour `POST /v1/pro/register`.
#[derive(Deserialize)]
pub struct ProRegisterCabinetBody {
    raison_sociale: String,
    siret: Option<String>,
    specialite: String,
}

/// Sous-corps praticien pour `POST /v1/pro/register`.
#[derive(Deserialize)]
pub struct ProRegisterPractitionerBody {
    first_name: String,
    last_name: String,
    rpps: Option<String>,
    adeli: Option<String>,
}

/// Corps de la requête `POST /v1/pro/register`.
#[derive(Deserialize)]
pub struct ProRegisterBody {
    email: String,
    password: String,
    cabinet: ProRegisterCabinetBody,
    practitioner: ProRegisterPractitionerBody,
}

/// Réponse de `POST /v1/pro/register`.
#[derive(Serialize)]
pub struct ProRegisterResponse {
    account_id: Uuid,
    cabinet_id: Uuid,
    provider_id: Uuid,
    access_token: String,
}

/// Claims JWT émis par `POST /v1/pro/register` — porte `cabinet_id` + `role`.
#[derive(Serialize, Deserialize)]
struct ProRegisterClaims {
    sub: Uuid,
    kind: String,
    cabinet_id: Uuid,
    role: String,
    exp: u64,
}

#[derive(Serialize)]
pub(crate) struct RegisterResponse {
    account_id: Uuid,
    access_token: String,
    refresh_token: String,
}

/// Réponse de `POST /v1/auth/mfa/enroll`.
#[derive(Serialize)]
pub struct MfaEnrollResponse {
    totp_secret: String,
    otpauth_url: String,
}

#[derive(Serialize)]
struct PatientClaims {
    sub: Uuid,
    kind: String,
    account_id: Uuid,
    exp: u64,
}

#[derive(Deserialize)]
pub struct ForgotPasswordBody {
    email: String,
}

/// `POST /v1/auth/password/forgot` — déclenche le reset de mot de passe.
///
/// Réponse toujours identique (200 + message neutre) que l'email existe ou non
/// (anti-énumération §1.8). Si l'email est connu, génère un token UUID, le stocke
/// hashé (SHA-256 via pgcrypto) avec une expiration d'une heure, puis notifie via
/// le mailer.
pub async fn forgot_password(
    State(state): State<AppState>,
    Json(body): Json<ForgotPasswordBody>,
) -> Json<Value> {
    let token = Uuid::new_v4().to_string();

    let result = sqlx::query(
        r#"
        UPDATE app_user
        SET
            password_reset_token      = encode(digest($2, 'sha256'), 'hex'),
            password_reset_expires_at = now() + interval '1 hour'
        WHERE email = $1
        "#,
    )
    .bind(&body.email)
    .bind(&token)
    .execute(&state.db)
    .await;

    match result {
        Ok(outcome) if outcome.rows_affected() > 0 => {
            state.mailer.send_password_reset(&body.email, &token);
        }
        Ok(_) => {}
        Err(e) => {
            tracing::error!(error = ?e, "forgot_password: db update failed");
        }
    }

    Json(json!({"message": "Si un compte existe, un email a été envoyé."}))
}

/// Claims JWT portées par les utilisateurs pro.
#[derive(Debug, Serialize, Deserialize)]
pub(crate) struct ProClaims {
    /// Identifiant de l'utilisateur (`app_user.id`).
    sub: Uuid,
    /// Type de compte : "pro".
    kind: String,
    exp: u64,
}

/// Corps de la requête `POST /v1/auth/password/reset`.
#[derive(Deserialize)]
pub struct ResetPasswordBody {
    token: String,
    new_password: String,
}

/// Erreur HTTP renvoyée au client.
pub(crate) enum AppError {
    Unauthorized,
    Unauthenticated,
    MfaRequired,
    ValidationError,
    Internal,
    EmailTaken,
    CguRequired,
    PasswordPolicy,
    Forbidden,
    InvalidToken,
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        match self {
            AppError::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "unauthorized"})),
            )
                .into_response(),
            AppError::Unauthenticated => (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "unauthenticated"})),
            )
                .into_response(),
            AppError::MfaRequired => (
                StatusCode::UNAUTHORIZED,
                Json(json!({"code": "mfa_required"})),
            )
                .into_response(),
            AppError::ValidationError => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "validation_error"})),
            )
                .into_response(),
            AppError::Internal => (
                StatusCode::INTERNAL_SERVER_ERROR,
                Json(json!({"code": "internal_error"})),
            )
                .into_response(),
            AppError::EmailTaken => {
                (StatusCode::CONFLICT, Json(json!({"code": "email_taken"}))).into_response()
            }
            AppError::CguRequired => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "cgu_required"})),
            )
                .into_response(),
            AppError::PasswordPolicy => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "password_policy"})),
            )
                .into_response(),
            AppError::Forbidden => {
                (StatusCode::FORBIDDEN, Json(json!({"code": "forbidden"}))).into_response()
            }
            AppError::InvalidToken => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "validation_error", "detail": "Token invalide ou expiré."})),
            )
                .into_response(),
        }
    }
}

/// Lit le JWT dans `Authorization: Bearer <token>`, vérifie la signature et `kind == "pro"`.
#[async_trait]
impl FromRequestParts<AppState> for ProClaims {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;

        let data =
            decode::<ProClaims>(token, &key, &validation).map_err(|_| AppError::Unauthorized)?;

        if data.claims.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        Ok(data.claims)
    }
}

/// Claims JWT génériques — valides pour les tokens patient et pro.
#[derive(Debug, Deserialize)]
pub(crate) struct UserClaims {
    pub(crate) sub: Uuid,
}

/// Claims JWT pour `GET /v1/me` — accepte patient et pro, extrait `kind` et `account_id`.
#[derive(Debug, Deserialize)]
pub(crate) struct MeClaims {
    pub(crate) sub: Uuid,
    pub(crate) kind: String,
    /// Présent uniquement dans les tokens patient.
    pub(crate) account_id: Option<Uuid>,
}

/// Appartenance à un cabinet.
#[derive(Serialize)]
pub struct CabinetMembership {
    cabinet_id: Uuid,
    role: String,
}

/// Réponse de `GET /v1/me`.
#[derive(Serialize)]
pub struct MeResponse {
    user_id: Uuid,
    email: String,
    kind: String,
    account_id: Option<Uuid>,
    memberships: Vec<CabinetMembership>,
}

/// `GET /v1/me` — retourne le profil du porteur du token (patient ou pro).
///
/// L'`account_id` est extrait directement du JWT pour les patients (pas de requête supplémentaire).
/// `memberships` est vide en MVP (table `cabinet_membership` non encore créée).
pub async fn me(
    State(state): State<AppState>,
    claims: MeClaims,
) -> Result<Json<MeResponse>, AppError> {
    let row = sqlx::query("SELECT email FROM app_user WHERE id = $1")
        .bind(claims.sub)
        .fetch_one(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;

    let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;

    Ok(Json(MeResponse {
        user_id: claims.sub,
        email,
        kind: claims.kind,
        account_id: claims.account_id,
        memberships: vec![],
    }))
}

/// Lit le JWT dans `Authorization: Bearer <token>`, vérifie la signature.
/// Accepte les tokens patient et pro, extrait `kind` et `account_id`.
#[async_trait]
impl FromRequestParts<AppState> for MeClaims {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;

        decode::<MeClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)
    }
}

/// Lit le JWT dans `Authorization: Bearer <token>`, vérifie la signature.
/// Accepte les tokens patient et pro.
#[async_trait]
impl FromRequestParts<AppState> for UserClaims {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        let auth = parts
            .headers
            .get("Authorization")
            .and_then(|v| v.to_str().ok())
            .ok_or(AppError::Unauthorized)?;

        let token = auth.strip_prefix("Bearer ").ok_or(AppError::Unauthorized)?;

        let key = DecodingKey::from_secret(state.jwt_secret.as_bytes());
        let mut validation = Validation::default();
        validation.validate_exp = true;

        decode::<UserClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)
    }
}

/// Corps de la requête `POST /v1/auth/refresh`.
#[derive(Deserialize)]
pub struct RefreshBody {
    refresh_token: String,
}

/// `POST /v1/auth/refresh` — rotation du refresh token.
///
/// Échange un refresh token valide contre un nouveau access token + nouveau refresh token.
/// L'ancien token est révoqué atomiquement dans la même transaction (rotation).
/// Token inconnu, révoqué ou expiré → `401`.
pub async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshBody>,
) -> Result<Json<LoginResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT app_user_id FROM refresh_token \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex') \
           AND revoked_at IS NULL \
           AND expires_at > now()",
    )
    .bind(&body.refresh_token)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Unauthenticated)?;
    let user_id: Uuid = row.try_get("app_user_id").map_err(|_| AppError::Internal)?;

    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let user_row = sqlx::query("SELECT kind FROM app_user WHERE id = $1")
        .bind(user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    let kind: String = user_row.try_get("kind").map_err(|_| AppError::Internal)?;

    let new_raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&new_raw_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    const EXPIRES_IN: u64 = 900;
    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + EXPIRES_IN;

    let access_token = if kind == "patient" {
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;
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
    };

    Ok(Json(LoginResponse {
        access_token,
        refresh_token: new_raw_token,
        token_type: "Bearer".to_string(),
        expires_in: EXPIRES_IN,
    }))
}

/// Corps de la requête `POST /v1/auth/logout`.
#[derive(Deserialize)]
pub struct LogoutBody {
    refresh_token: String,
}

/// `POST /v1/auth/logout` — révoque le refresh token de l'utilisateur authentifié.
///
/// Soft-delete : SET `revoked_at = NOW()`. Vérifie que `refresh_token.app_user_id == claims.sub`
/// pour interdire la révocation cross-user (`403`). Idempotent si le token est
/// inconnu ou déjà révoqué (`204` dans les deux cas).
pub async fn logout(
    State(state): State<AppState>,
    claims: UserClaims,
    Json(body): Json<LogoutBody>,
) -> Result<StatusCode, AppError> {
    let row = sqlx::query(
        "SELECT app_user_id FROM refresh_token \
         WHERE token_hash = encode(digest($1, 'sha256'), 'hex')",
    )
    .bind(&body.refresh_token)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(r) = row {
        let owner_id: Uuid = r.try_get("app_user_id").map_err(|_| AppError::Internal)?;
        if owner_id != claims.sub {
            return Err(AppError::Forbidden);
        }
        sqlx::query(
            "UPDATE refresh_token SET revoked_at = now() \
             WHERE token_hash = encode(digest($1, 'sha256'), 'hex') \
               AND revoked_at IS NULL",
        )
        .bind(&body.refresh_token)
        .execute(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    Ok(StatusCode::NO_CONTENT)
}

/// `POST /v1/auth/mfa/enroll` — démarre l'enrôlement TOTP (pro uniquement).
///
/// Génère un secret TOTP aléatoire et retourne l'URL `otpauth://` pour affichage QR.
/// Le secret n'est PAS persisté ici — il le sera lors de la vérification via `/mfa/verify`.
pub async fn mfa_enroll(_claims: ProClaims) -> Result<Json<MfaEnrollResponse>, AppError> {
    let secret = Secret::generate_secret();
    let totp_secret = secret.to_encoded().to_string();
    let otpauth_url = format!(
        "otpauth://totp/Nubia%20Health?secret={}&issuer=Nubia%20Health&algorithm=SHA1&digits=6&period=30",
        totp_secret
    );
    Ok(Json(MfaEnrollResponse {
        totp_secret,
        otpauth_url,
    }))
}

/// Corps de la requête `POST /v1/auth/mfa/verify`.
#[derive(Deserialize)]
pub struct MfaVerifyBody {
    /// Secret TOTP Base32 retourné par `/mfa/enroll`.
    totp_secret: String,
    /// Code TOTP à 6 chiffres saisi par l'utilisateur.
    totp_code: String,
}

/// `POST /v1/auth/mfa/verify` — valide le code TOTP et active la MFA.
///
/// Le code TOTP est validé AVANT toute persistance (règle métier : ne pas activer
/// sur code invalide).
pub async fn mfa_verify(
    State(state): State<AppState>,
    claims: ProClaims,
    Json(body): Json<MfaVerifyBody>,
) -> Result<Json<serde_json::Value>, AppError> {
    let secret_bytes = Secret::Encoded(body.totp_secret.clone())
        .to_bytes()
        .map_err(|_| AppError::ValidationError)?;

    let totp = TOTP::new(Algorithm::SHA1, 6, 1, 30, secret_bytes)
        .map_err(|_| AppError::ValidationError)?;

    let is_valid = totp
        .check_current(&body.totp_code)
        .map_err(|_| AppError::Internal)?;

    if !is_valid {
        return Err(AppError::ValidationError);
    }

    sqlx::query!(
        "UPDATE app_user SET mfa_secret = $1, mfa_enabled = true, updated_at = now() WHERE id = $2",
        body.totp_secret,
        claims.sub,
    )
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "MFA activée."})))
}

/// `POST /v1/auth/register` — crée un compte patient (app_user + patient_account +
/// consent_record) en transaction atomique, puis émet les tokens.
pub async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterBody>,
) -> Result<(StatusCode, Json<RegisterResponse>), AppError> {
    if !body.accept_cgu {
        return Err(AppError::CguRequired);
    }
    if body.password.len() < 8 || !body.password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) VALUES ($1, $2, 'patient') RETURNING id",
    )
    .bind(&body.email)
    .bind(&password_hash)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::EmailTaken
        } else {
            AppError::Internal
        }
    })?;
    let user_id: Uuid = row.try_get(0).map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO patient_account (app_user_id, first_name, last_name) VALUES ($1, '', '') RETURNING id",
    )
    .bind(user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let account_id: Uuid = row.try_get(0).map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO consent_record (app_user_id, purpose, granted, granted_at, cgu_version) \
         VALUES ($1, 'soins', true, now(), $2)",
    )
    .bind(user_id)
    .bind(&body.cgu_version)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let raw_token = Uuid::new_v4().to_string();
    sqlx::query(
        r#"INSERT INTO refresh_token (app_user_id, token_hash, expires_at)
           VALUES ($1, encode(digest($2, 'sha256'), 'hex'), now() + interval '30 days')"#,
    )
    .bind(user_id)
    .bind(&raw_token)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + 900;
    let claims = PatientClaims {
        sub: user_id,
        kind: "patient".to_string(),
        account_id,
        exp,
    };
    let access_token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::CREATED,
        Json(RegisterResponse {
            account_id,
            access_token,
            refresh_token: raw_token,
        }),
    ))
}

/// `POST /v1/auth/login` — authentifie un patient ou un pro, émet access + refresh tokens.
///
/// Réponse neutre sur credentials incorrects (anti-énumération §1.8).
/// Si le compte pro a `totp_enabled = true` et qu'aucun `mfa_code` n'est fourni → `401 mfa_required`.
pub async fn login(
    State(state): State<AppState>,
    Json(body): Json<LoginBody>,
) -> Result<Json<LoginResponse>, AppError> {
    let row = sqlx::query(
        "SELECT id, password_hash, kind, totp_enabled, totp_secret \
         FROM app_user WHERE email = $1",
    )
    .bind(&body.email)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::Unauthenticated)?;

    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let password_hash: String = row
        .try_get("password_hash")
        .map_err(|_| AppError::Internal)?;
    let kind: String = row.try_get("kind").map_err(|_| AppError::Internal)?;
    let totp_enabled: bool = row
        .try_get("totp_enabled")
        .map_err(|_| AppError::Internal)?;
    let totp_secret: Option<String> = row.try_get("totp_secret").map_err(|_| AppError::Internal)?;

    let parsed_hash = PasswordHash::new(&password_hash).map_err(|_| AppError::Internal)?;
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

    let access_token = if kind == "patient" {
        let acct_row = sqlx::query("SELECT id FROM patient_account WHERE app_user_id = $1")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;

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
    }))
}

/// `POST /v1/auth/password/reset` — finalise le reset via un token à usage unique.
///
/// Vérifie le token (SHA-256, non expiré), met à jour `password_hash`,
/// puis invalide le token (`NULL`). Token inexistant ou expiré → `422`.
pub async fn reset_password(
    State(state): State<AppState>,
    Json(body): Json<ResetPasswordBody>,
) -> Result<Json<Value>, AppError> {
    if body.new_password.len() < 8 || !body.new_password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    let row = sqlx::query(
        "SELECT id FROM app_user \
         WHERE password_reset_token = encode(digest($1, 'sha256'), 'hex') \
           AND password_reset_expires_at > now()",
    )
    .bind(&body.token)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::InvalidToken)?;
    let user_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.new_password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    sqlx::query(
        "UPDATE app_user \
         SET password_hash = $1, \
             password_reset_token = NULL, \
             password_reset_expires_at = NULL, \
             updated_at = now() \
         WHERE id = $2",
    )
    .bind(&password_hash)
    .bind(user_id)
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(Json(json!({"message": "Mot de passe réinitialisé."})))
}

/// `POST /v1/pro/register` — crée un compte pro + cabinet + membership admin + provider
/// en une transaction atomique. Émet un JWT portant `cabinet_id` et `role:"admin"`.
pub async fn pro_register(
    State(state): State<AppState>,
    Json(body): Json<ProRegisterBody>,
) -> Result<(StatusCode, Json<ProRegisterResponse>), AppError> {
    if body.password.len() < 8 || !body.password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    let salt = SaltString::generate(&mut OsRng);
    let password_hash = Argon2::default()
        .hash_password(body.password.as_bytes(), &salt)
        .map_err(|_| AppError::Internal)?
        .to_string();

    // Pre-generate cabinet UUID so we can SET LOCAL app.current_cabinet_id before the insert.
    // cabinet has FORCE RLS: WITH CHECK requires id = current_setting('app.current_cabinet_id').
    let cabinet_id = Uuid::new_v4();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // app_user has no RLS — insert before setting the tenant GUC.
    let user_row = sqlx::query(
        "INSERT INTO app_user (email, password_hash, kind) VALUES ($1, $2, 'pro') RETURNING id",
    )
    .bind(&body.email)
    .bind(&password_hash)
    .fetch_one(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::EmailTaken
        } else {
            AppError::Internal
        }
    })?;
    let user_id: Uuid = user_row.try_get(0).map_err(|_| AppError::Internal)?;

    // Scope the tenant GUC to this transaction (SET LOCAL) so subsequent inserts
    // pass the cabinet / cabinet_membership / provider RLS WITH CHECK.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO cabinet (id, raison_sociale, siret, specialite) VALUES ($1, $2, $3, $4)",
    )
    .bind(cabinet_id)
    .bind(&body.cabinet.raison_sociale)
    .bind(&body.cabinet.siret)
    .bind(&body.cabinet.specialite)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role) VALUES ($1, $2, 'admin')",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let display_name = format!(
        "{} {}",
        body.practitioner.first_name, body.practitioner.last_name
    );
    let provider_row = sqlx::query(
        "INSERT INTO provider (cabinet_id, user_id, display_name, rpps, adeli) \
         VALUES ($1, $2, $3, $4, $5) RETURNING id",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(&display_name)
    .bind(&body.practitioner.rpps)
    .bind(&body.practitioner.adeli)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let provider_id: Uuid = provider_row.try_get(0).map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let exp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
        + 900;
    let claims = ProRegisterClaims {
        sub: user_id,
        kind: "pro".to_string(),
        cabinet_id,
        role: "admin".to_string(),
        exp,
    };
    let access_token = encode(
        &Header::default(),
        &claims,
        &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
    )
    .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::CREATED,
        Json(ProRegisterResponse {
            account_id: user_id,
            cabinet_id,
            provider_id,
            access_token,
        }),
    ))
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}
