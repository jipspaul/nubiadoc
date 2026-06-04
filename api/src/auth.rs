//! Handlers d'authentification (routes publiques `/v1/auth/*`).

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString},
    Argon2,
};
use async_trait::async_trait;
use axum::{
    extract::{Extension, FromRequestParts, Multipart, Path, State},
    http::{request::Parts, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::Row;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use totp_rs::{Algorithm, Secret, TOTP};
use uuid::Uuid;

use crate::{AppState, JobDispatcher};

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
    Conflict,
    NotFound,
    ProviderNotVerified,
    MemberAlreadyExists,
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
            AppError::Conflict => (
                StatusCode::CONFLICT,
                Json(json!({"code": "verification_pending"})),
            )
                .into_response(),
            AppError::NotFound => {
                (StatusCode::NOT_FOUND, Json(json!({"code": "not_found"}))).into_response()
            }
            AppError::ProviderNotVerified => (
                StatusCode::CONFLICT,
                Json(json!({"code": "provider_not_verified"})),
            )
                .into_response(),
            AppError::MemberAlreadyExists => (
                StatusCode::CONFLICT,
                Json(json!({"code": "member_already_exists"})),
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

/// Réponse de `GET /v1/cabinet`.
#[derive(Serialize)]
pub struct CabinetResponse {
    id: Uuid,
    name: String,
    siret: Option<String>,
    settings: Value,
}

/// Forme interne : extrait `kind` et `cabinet_id` optionnel pour le double-décodage.
#[derive(Deserialize)]
struct KindClaims {
    kind: String,
    cabinet_id: Option<Uuid>,
    sub: Uuid,
}

/// Claims JWT pro (tous rôles) — extrait du token portant `cabinet_id`.
///
/// Renvoie `401` si le token est absent ou invalide, `403` si `kind != "pro"`.
#[derive(Debug, Deserialize)]
pub(crate) struct ProMemberClaims {
    pub(crate) sub: Uuid,
    pub(crate) cabinet_id: Uuid,
}

#[async_trait]
impl FromRequestParts<AppState> for ProMemberClaims {
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

        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        let cabinet_id = basic.cabinet_id.ok_or(AppError::Unauthorized)?;

        Ok(ProMemberClaims {
            sub: basic.sub,
            cabinet_id,
        })
    }
}

/// `GET /v1/cabinet` — retourne le cabinet courant du porteur du token pro.
///
/// `cabinet_id` extrait du JWT (jamais du body/query). RLS-scoped via `set_config`.
pub async fn get_cabinet(
    State(state): State<AppState>,
    claims: ProMemberClaims,
) -> Result<Json<CabinetResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query("SELECT id, raison_sociale, siret, settings FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let name: String = row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let siret: Option<String> = row
        .try_get::<Option<String>, _>("siret")
        .map_err(|_| AppError::Internal)?
        .map(|s| s.trim().to_string());
    let settings: Value = row.try_get("settings").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        "cabinet settings queried"
    );

    Ok(Json(CabinetResponse {
        id,
        name,
        siret,
        settings,
    }))
}

/// Corps de la requête `PATCH /v1/cabinet`.
#[derive(Deserialize)]
pub struct PatchCabinetBody {
    pub name: Option<String>,
    pub address: Option<String>,
    pub phone: Option<String>,
    pub siret: Option<String>,
    pub settings: Option<Value>,
}

/// `PATCH /v1/cabinet` — édite les réglages/infos pratiques du cabinet (admin uniquement).
///
/// Merge patch : les champs absents du body restent inchangés. `address` et `phone`
/// sont fusionnés dans le JSONB `settings`. Toute modification est auditée dans `audit_log`.
pub async fn patch_cabinet(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<PatchCabinetBody>,
) -> Result<Json<CabinetResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Snapshot avant modification pour l'audit log.
    let old = sqlx::query("SELECT raison_sociale, siret, settings FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::NotFound)?;
    let old_name: String = old
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let old_siret: Option<String> = old.try_get("siret").map_err(|_| AppError::Internal)?;
    let old_settings: Value = old.try_get("settings").map_err(|_| AppError::Internal)?;

    // Construit le delta settings : address, phone et settings explicites fusionnés.
    let mut settings_delta = serde_json::Map::new();
    if let Some(addr) = &body.address {
        settings_delta.insert("address".to_string(), Value::String(addr.clone()));
    }
    if let Some(phone) = &body.phone {
        settings_delta.insert("phone".to_string(), Value::String(phone.clone()));
    }
    if let Some(s) = &body.settings {
        if let Some(obj) = s.as_object() {
            for (k, v) in obj {
                settings_delta.insert(k.clone(), v.clone());
            }
        }
    }
    let settings_delta = Value::Object(settings_delta);

    let row = sqlx::query(
        "UPDATE cabinet
         SET
             raison_sociale = COALESCE($1, raison_sociale),
             siret          = COALESCE($2, siret),
             settings       = settings || $3,
             updated_at     = now()
         WHERE id = $4
         RETURNING id, raison_sociale, siret, settings",
    )
    .bind(body.name.as_deref())
    .bind(body.siret.as_deref())
    .bind(&settings_delta)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let new_name: String = row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let new_siret: Option<String> = row
        .try_get::<Option<String>, _>("siret")
        .map_err(|_| AppError::Internal)?;
    let new_settings: Value = row.try_get("settings").map_err(|_| AppError::Internal)?;

    // Construit les métadonnées d'audit : un objet {champ: {old, new}} par champ modifié.
    let mut changes = serde_json::Map::new();
    if body.name.is_some() && new_name != old_name {
        changes.insert(
            "name".to_string(),
            json!({"old": old_name, "new": new_name}),
        );
    }
    if body.siret.is_some() && new_siret != old_siret {
        changes.insert(
            "siret".to_string(),
            json!({"old": old_siret, "new": new_siret}),
        );
    }
    let settings_changed = settings_delta.as_object().is_some_and(|m| !m.is_empty());
    if settings_changed {
        changes.insert(
            "settings".to_string(),
            json!({"old": old_settings, "new": new_settings}),
        );
    }

    if !changes.is_empty() {
        sqlx::query(
            "INSERT INTO audit_log \
             (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
             VALUES ($1, $2, 'admin', 'update_cabinet', 'cabinet', $3, $4)",
        )
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .bind(claims.cabinet_id)
        .bind(Value::Object(changes))
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let siret = new_siret.map(|s| s.trim().to_string());

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        "cabinet updated"
    );

    Ok(Json(CabinetResponse {
        id,
        name: new_name,
        siret,
        settings: new_settings,
    }))
}

/// Réponse de `GET /v1/pro/verification`.
#[derive(Serialize)]
pub struct ProVerificationStatusResponse {
    verification_id: Uuid,
    id_type: String,
    identifier: String,
    status: String,
    created_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    resolved_at: Option<String>,
}

/// `GET /v1/pro/verification` — retourne le statut de la dernière vérification ANS du praticien.
///
/// Renvoie `200` avec le dernier enregistrement `provider_verification` (ORDER BY created_at DESC).
/// Aucun enregistrement → `404`.
pub async fn get_pro_verification(
    State(state): State<AppState>,
    claims: ProAdminClaims,
) -> Result<Json<ProVerificationStatusResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let provider_row =
        sqlx::query("SELECT id FROM provider WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;
    let provider_id: Uuid = provider_row.try_get(0).map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT id, id_type, identifier, status, created_at, resolved_at \
         FROM provider_verification \
         WHERE provider_id = $1 \
         ORDER BY created_at DESC LIMIT 1",
    )
    .bind(provider_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let row = row.ok_or(AppError::NotFound)?;

    let verification_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let id_type: String = row.try_get("id_type").map_err(|_| AppError::Internal)?;
    let identifier: String = row.try_get("identifier").map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let resolved_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("resolved_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %provider_id,
        verification_id = %verification_id,
        "provider verification status queried"
    );

    Ok(Json(ProVerificationStatusResponse {
        verification_id,
        id_type,
        identifier,
        status,
        created_at: created_at.to_rfc3339(),
        resolved_at: resolved_at.map(|t| t.to_rfc3339()),
    }))
}

fn is_unique_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23505")
    )
}

/// Claims JWT pro avec rôle admin — extrait du token émis par `POST /v1/pro/register`.
///
/// `exp` absent du struct : validé par jsonwebtoken sur le JSON brut (`validate_exp = true`).
#[derive(Debug, Deserialize)]
pub(crate) struct ProAdminClaims {
    sub: Uuid,
    kind: String,
    /// `cabinet_id` porté par le token (jamais du body/query — invariant tenancy).
    cabinet_id: Uuid,
    role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for ProAdminClaims {
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

        let claims = decode::<ProAdminClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.kind != "pro" {
            return Err(AppError::Forbidden);
        }
        if claims.role != "admin" {
            return Err(AppError::Forbidden);
        }

        Ok(claims)
    }
}

/// Claims JWT pro avec rôle praticien (`practitioner` ou `admin`) — rejette `secretary`.
///
/// Permet l'accès aux endpoints cliniques non accessibles au secrétariat (§07 §4.1).
#[derive(Debug, Deserialize)]
pub(crate) struct ProPractitionerClaims {
    sub: Uuid,
    kind: String,
    cabinet_id: Uuid,
    role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for ProPractitionerClaims {
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

        let claims = decode::<ProPractitionerClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.kind != "pro" {
            return Err(AppError::Forbidden);
        }
        if claims.role == "secretary" {
            return Err(AppError::Forbidden);
        }

        Ok(claims)
    }
}

/// Corps de la requête `PATCH /v1/cabinet/provider`.
#[derive(Deserialize)]
pub struct PatchProviderBody {
    bio: Option<String>,
    specialite: Option<String>,
    langues: Option<Vec<String>>,
    pmr: Option<bool>,
}

/// Réponse de `PATCH /v1/cabinet/provider`.
#[derive(Serialize)]
pub struct ProviderProfileResponse {
    id: Uuid,
    bio: Option<String>,
    specialite: Option<String>,
    langues: Option<Vec<String>>,
    pmr: Option<bool>,
    is_listed: bool,
    rpps_verified: bool,
}

/// `PATCH /v1/cabinet/provider` — met à jour le profil public du praticien.
///
/// Champs absents du body = non modifiés (COALESCE SQL). `is_listed` et
/// `rpps_verified` ne sont pas modifiables ici (§07 §4.7). Rôle `secretary` → 403.
pub async fn patch_cabinet_provider(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<PatchProviderBody>,
) -> Result<Json<ProviderProfileResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "UPDATE provider
         SET
             bio        = COALESCE($1, bio),
             specialite = COALESCE($2, specialite),
             languages  = COALESCE($3::text[], languages),
             pmr        = COALESCE($4, pmr)
         WHERE cabinet_id = $5 AND user_id = $6
         RETURNING id, bio, specialite, languages, pmr, is_listed, rpps_verified",
    )
    .bind(&body.bio)
    .bind(&body.specialite)
    .bind(&body.langues)
    .bind(body.pmr)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let bio: Option<String> = row.try_get("bio").map_err(|_| AppError::Internal)?;
    let specialite: Option<String> = row.try_get("specialite").map_err(|_| AppError::Internal)?;
    let langues: Option<Vec<String>> = row.try_get("languages").map_err(|_| AppError::Internal)?;
    let pmr: Option<bool> = row.try_get("pmr").map_err(|_| AppError::Internal)?;
    let is_listed: bool = row.try_get("is_listed").map_err(|_| AppError::Internal)?;
    let rpps_verified: bool = row
        .try_get("rpps_verified")
        .map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        provider_id = %id,
        "provider profile updated"
    );

    Ok(Json(ProviderProfileResponse {
        id,
        bio,
        specialite,
        langues,
        pmr,
        is_listed,
        rpps_verified,
    }))
}

/// Un membre du cabinet tel que retourné par `GET /v1/cabinet/members`.
#[derive(Serialize)]
pub struct CabinetMemberItem {
    user_id: Uuid,
    email: String,
    first_name: Option<String>,
    last_name: Option<String>,
    role: String,
    active: bool,
    joined_at: String,
}

/// `GET /v1/cabinet/members` — liste tous les membres (y compris inactifs) du cabinet courant.
///
/// Rôle `admin` requis. `cabinet_id` toujours extrait du JWT. RLS scoped via `SET LOCAL`.
pub async fn get_cabinet_members(
    State(state): State<AppState>,
    claims: ProAdminClaims,
) -> Result<Json<Vec<CabinetMemberItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT cm.user_id, au.email, cm.role, cm.active, cm.created_at AS joined_at \
         FROM cabinet_membership cm \
         JOIN app_user au ON au.id = cm.user_id \
         WHERE cm.cabinet_id = $1 \
         ORDER BY cm.created_at ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let members = rows
        .into_iter()
        .map(|row| {
            let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
            let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;
            let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;
            let active: bool = row.try_get("active").map_err(|_| AppError::Internal)?;
            let joined_at: chrono::DateTime<chrono::Utc> =
                row.try_get("joined_at").map_err(|_| AppError::Internal)?;
            Ok(CabinetMemberItem {
                user_id,
                email,
                first_name: None,
                last_name: None,
                role,
                active,
                joined_at: joined_at.to_rfc3339(),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        count = members.len(),
        "cabinet members listed"
    );

    Ok(Json(members))
}

/// Corps de la requête `PUT /v1/cabinet/provider/listing`.
#[derive(Deserialize)]
pub struct PutListingBody {
    pub online: bool,
}

/// Réponse de `PUT /v1/cabinet/provider/listing`.
#[derive(Serialize)]
pub struct ListingResponse {
    pub is_listed: bool,
}

/// `PUT /v1/cabinet/provider/listing` — active ou désactive la mise en ligne du praticien.
///
/// Règle métier (§07 §4.7, §05 §9.3) : `is_listed=true` uniquement si `rpps_verified=true`.
/// Sinon → `409 provider_not_verified`. Rôle `admin` requis.
pub async fn put_cabinet_provider_listing(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<PutListingBody>,
) -> Result<Json<ListingResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    if body.online {
        let row = sqlx::query(
            "SELECT rpps_verified FROM provider WHERE cabinet_id = $1 AND user_id = $2",
        )
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

        let rpps_verified: bool = row
            .try_get("rpps_verified")
            .map_err(|_| AppError::Internal)?;
        if !rpps_verified {
            return Err(AppError::ProviderNotVerified);
        }
    }

    let row = sqlx::query(
        "UPDATE provider SET is_listed = $1 \
         WHERE cabinet_id = $2 AND user_id = $3 \
         RETURNING is_listed",
    )
    .bind(body.online)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let is_listed: bool = row.try_get("is_listed").map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        is_listed,
        "provider listing updated"
    );

    Ok(Json(ListingResponse { is_listed }))
}

/// Corps de la requête `POST /v1/cabinet/members`.
#[derive(Deserialize)]
pub struct PostCabinetMemberBody {
    email: String,
    role: String,
    first_name: String,
    last_name: String,
    rpps: Option<String>,
}

/// `POST /v1/cabinet/members` — crée un compte collaborateur et l'invite par email.
///
/// Si l'email est inconnu : crée `app_user` (password_hash NULL) + token invite 72 h
/// stocké dans `password_reset_token`. Si l'email est déjà membre du même cabinet → `409`.
/// Si `rpps` est fourni et `role=practitioner` → crée une entrée `provider`. Rôle `admin` requis.
pub async fn post_cabinet_members(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<PostCabinetMemberBody>,
) -> Result<(StatusCode, Json<CabinetMemberItem>), AppError> {
    if !["practitioner", "secretary", "admin"].contains(&body.role.as_str()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // app_user n'a pas de RLS — lookup direct par email.
    let existing = sqlx::query("SELECT id FROM app_user WHERE email = $1")
        .bind(&body.email)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Token brut conservé pour l'email d'invite (uniquement si nouveau compte).
    let mut raw_invite_token: Option<String> = None;

    let user_id: Uuid = if let Some(row) = existing {
        row.try_get("id").map_err(|_| AppError::Internal)?
    } else {
        let token = Uuid::new_v4().to_string();
        let row = sqlx::query(
            "INSERT INTO app_user \
             (email, password_hash, kind, first_name, last_name, \
              password_reset_token, password_reset_expires_at) \
             VALUES ($1, NULL, 'pro', $2, $3, \
                     encode(digest($4, 'sha256'), 'hex'), now() + interval '72 hours') \
             RETURNING id",
        )
        .bind(&body.email)
        .bind(&body.first_name)
        .bind(&body.last_name)
        .bind(&token)
        .fetch_one(&mut *tx)
        .await
        .map_err(|e| {
            if is_unique_violation(&e) {
                AppError::EmailTaken
            } else {
                AppError::Internal
            }
        })?;
        raw_invite_token = Some(token);
        row.try_get(0).map_err(|_| AppError::Internal)?
    };

    // Crée le membership — UNIQUE (cabinet_id, user_id) → 409 si doublon.
    sqlx::query(
        "INSERT INTO cabinet_membership (cabinet_id, user_id, role, active) \
         VALUES ($1, $2, $3, true)",
    )
    .bind(claims.cabinet_id)
    .bind(user_id)
    .bind(&body.role)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            AppError::MemberAlreadyExists
        } else {
            AppError::Internal
        }
    })?;

    // Si rpps fourni et role=practitioner → crée l'entrée provider (RLS scoped via GUC).
    if body.role == "practitioner" {
        if let Some(ref rpps) = body.rpps {
            let display_name = format!("{} {}", body.first_name, body.last_name);
            sqlx::query(
                "INSERT INTO provider (cabinet_id, user_id, display_name, rpps) \
                 VALUES ($1, $2, $3, $4)",
            )
            .bind(claims.cabinet_id)
            .bind(user_id)
            .bind(&display_name)
            .bind(rpps)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        }
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Email d'invite envoyé après commit (fire-and-forget, nouveau compte uniquement).
    if let Some(ref token) = raw_invite_token {
        state.mailer.send_invite(&body.email, token);
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %user_id,
        role = %body.role,
        new_account = raw_invite_token.is_some(),
        "cabinet member created"
    );

    let joined_at = chrono::Utc::now().to_rfc3339();
    Ok((
        StatusCode::CREATED,
        Json(CabinetMemberItem {
            user_id,
            email: body.email,
            first_name: Some(body.first_name),
            last_name: Some(body.last_name),
            role: body.role,
            active: true,
            joined_at,
        }),
    ))
}

/// Claims JWT d'un patient — extrait `account_id` et `sub` depuis le token.
///
/// Renvoie `401` si le token est absent/invalide, `403` si `kind != "patient"`.
#[derive(Debug, Deserialize)]
pub(crate) struct PatientAccountClaims {
    pub(crate) sub: Uuid,
    pub(crate) account_id: Uuid,
    kind: String,
}

#[async_trait]
impl FromRequestParts<AppState> for PatientAccountClaims {
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

        let claims = decode::<PatientAccountClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.kind != "patient" {
            return Err(AppError::Forbidden);
        }

        Ok(claims)
    }
}

/// Réponse de `GET /v1/account`.
#[derive(Serialize)]
pub struct AccountResponse {
    id: Uuid,
    first_name: String,
    last_name: String,
    email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    phone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    birth_date: Option<String>,
    created_at: String,
}

/// `GET /v1/account` — retourne l'identité et les coordonnées du compte patient.
///
/// Données de niveau plateforme (portables entre cabinets). `nss` et colonnes chiffrées
/// ne sont jamais renvoyés (`05` §10.1). Auth JWT patient obligatoire.
pub async fn get_account(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<AccountResponse>, AppError> {
    let row = sqlx::query(
        "SELECT pa.id, pa.first_name, pa.last_name, pa.phone, pa.birth_date, pa.created_at, \
                au.email \
         FROM patient_account pa \
         JOIN app_user au ON au.id = pa.app_user_id \
         WHERE pa.id = $1 AND pa.app_user_id = $2 AND pa.deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .bind(claims.sub)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let phone: Option<String> = row.try_get("phone").map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        user_id = %claims.sub,
        "patient account queried"
    );

    Ok(Json(AccountResponse {
        id,
        first_name,
        last_name,
        email,
        phone,
        birth_date: birth_date.map(|d| d.to_string()),
        created_at: created_at.to_rfc3339(),
    }))
}

/// Corps de la requête `POST /v1/pro/verification`.
#[derive(Deserialize)]
pub struct ProVerificationBody {
    id_type: String,
    identifier: String,
}

/// Réponse de `POST /v1/pro/verification`.
#[derive(Serialize)]
pub struct ProVerificationResponse {
    verification_id: Uuid,
    status: String,
}

/// Corps de la requête `PATCH /v1/cabinet/members/{user_id}`.
#[derive(Deserialize)]
pub struct PatchCabinetMemberBody {
    role: Option<String>,
}

/// Réponse de `PATCH /v1/cabinet/members/{user_id}`.
#[derive(Serialize)]
pub struct PatchCabinetMemberResponse {
    user_id: Uuid,
    role: String,
}

/// `PATCH /v1/cabinet/members/{user_id}` — change le rôle d'un collaborateur (admin uniquement).
///
/// Merge patch : seul `role` est modifiable ici. Admin ne peut pas changer son propre rôle → `403`.
/// `user_id` absent du cabinet courant → `404`. Chaque changement de rôle est audité.
pub async fn patch_cabinet_member(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(target_user_id): Path<Uuid>,
    Json(body): Json<PatchCabinetMemberBody>,
) -> Result<Json<PatchCabinetMemberResponse>, AppError> {
    if target_user_id == claims.sub {
        return Err(AppError::Forbidden);
    }

    if let Some(ref role) = body.role {
        if !["practitioner", "secretary", "admin"].contains(&role.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT role FROM cabinet_membership \
         WHERE cabinet_id = $1 AND user_id = $2",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let old_role: String = current.try_get("role").map_err(|_| AppError::Internal)?;
    let new_role = body.role.unwrap_or_else(|| old_role.clone());

    let row = sqlx::query(
        "UPDATE cabinet_membership \
         SET role = $1 \
         WHERE cabinet_id = $2 AND user_id = $3 \
         RETURNING role",
    )
    .bind(&new_role)
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let updated_role: String = row.try_get("role").map_err(|_| AppError::Internal)?;

    if new_role != old_role {
        sqlx::query(
            "INSERT INTO audit_log \
             (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
             VALUES ($1, $2, 'admin', 'update_member_role', 'cabinet_membership', $3, $4)",
        )
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .bind(target_user_id)
        .bind(json!({"old_role": old_role, "new_role": updated_role}))
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        actor_id = %claims.sub,
        target_user_id = %target_user_id,
        old_role = %old_role,
        new_role = %updated_role,
        "cabinet member role updated"
    );

    Ok(Json(PatchCabinetMemberResponse {
        user_id: target_user_id,
        role: updated_role,
    }))
}

/// `DELETE /v1/cabinet/members/{user_id}` — révoque l'accès d'un collaborateur (soft-delete).
///
/// Met `cabinet_membership.active = false` et `left_at = now()`. Invalide également
/// tous les refresh tokens actifs du membre. Admin ne peut pas se supprimer lui-même → `403`.
/// `user_id` absent ou déjà inactif dans le cabinet → `404`.
pub async fn delete_cabinet_member(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Path(target_user_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    if target_user_id == claims.sub {
        return Err(AppError::Forbidden);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie que le membre existe et est actif dans ce cabinet.
    sqlx::query(
        "SELECT id FROM cabinet_membership \
         WHERE cabinet_id = $1 AND user_id = $2 AND active = true",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    sqlx::query(
        "UPDATE cabinet_membership \
         SET active = false, left_at = now() \
         WHERE cabinet_id = $1 AND user_id = $2",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Révoque toutes les sessions actives du membre (refresh_token sans cabinet_id → révocation globale).
    sqlx::query(
        "UPDATE refresh_token SET revoked_at = now() \
         WHERE app_user_id = $1 AND revoked_at IS NULL",
    )
    .bind(target_user_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        actor_id = %claims.sub,
        target_user_id = %target_user_id,
        "cabinet member deactivated"
    );

    Ok(StatusCode::NO_CONTENT)
}

/// Sous-corps adresse pour `PATCH /v1/account`.
#[derive(Deserialize)]
pub struct PatchAccountAddress {
    line1: Option<String>,
    city: Option<String>,
    zip: Option<String>,
    country: Option<String>,
}

/// Corps de la requête `PATCH /v1/account`.
#[derive(Deserialize)]
pub struct PatchAccountBody {
    first_name: Option<String>,
    last_name: Option<String>,
    phone: Option<String>,
    address: Option<PatchAccountAddress>,
    /// Présence → `422` : non modifiable via cette route.
    email: Option<Value>,
    /// Présence → `422` : non modifiable via cette route.
    birth_date: Option<Value>,
}

/// Construit le delta JSONB à fusionner dans `contact` à partir de l'adresse fournie.
fn contact_delta(address: Option<&PatchAccountAddress>) -> Value {
    let mut map = serde_json::Map::new();
    if let Some(addr) = address {
        let mut obj = serde_json::Map::new();
        if let Some(v) = &addr.line1 {
            obj.insert("line1".into(), Value::String(v.clone()));
        }
        if let Some(v) = &addr.city {
            obj.insert("city".into(), Value::String(v.clone()));
        }
        if let Some(v) = &addr.zip {
            obj.insert("zip".into(), Value::String(v.clone()));
        }
        if let Some(v) = &addr.country {
            obj.insert("country".into(), Value::String(v.clone()));
        }
        if !obj.is_empty() {
            map.insert("address".into(), Value::Object(obj));
        }
    }
    Value::Object(map)
}

/// `PATCH /v1/account` — met à jour les coordonnées du compte patient (partiel, audité).
///
/// Champs absents = non modifiés (COALESCE). `email` et `birth_date` ne sont pas
/// modifiables ici → `422`. Chaque PATCH génère un log d'audit (`06` E3.1.2).
/// `patient_account` est hors RLS cabinet : audit_log utilise le nil UUID comme
/// sentinel cabinet_id de niveau plateforme.
pub async fn patch_account(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PatchAccountBody>,
) -> Result<Json<AccountResponse>, AppError> {
    if body.email.is_some() || body.birth_date.is_some() {
        return Err(AppError::ValidationError);
    }

    let delta = contact_delta(body.address.as_ref());

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Snapshot avant modification (diff d'audit).
    let old = sqlx::query(
        "SELECT first_name, last_name, phone FROM patient_account \
         WHERE id = $1 AND app_user_id = $2 AND deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let old_first_name: String = old.try_get("first_name").map_err(|_| AppError::Internal)?;
    let old_last_name: String = old.try_get("last_name").map_err(|_| AppError::Internal)?;
    let old_phone: Option<String> = old.try_get("phone").map_err(|_| AppError::Internal)?;

    // Mise à jour + récupération du profil mis à jour (CTE pour inclure email).
    let row = sqlx::query(
        "WITH upd AS ( \
           UPDATE patient_account \
           SET \
             first_name = COALESCE($1, first_name), \
             last_name  = COALESCE($2, last_name), \
             phone      = COALESCE($3, phone), \
             contact    = contact || $4, \
             updated_at = now() \
           WHERE id = $5 AND app_user_id = $6 AND deleted_at IS NULL \
           RETURNING id, first_name, last_name, phone, birth_date, created_at, app_user_id \
         ) \
         SELECT u.id, u.first_name, u.last_name, u.phone, u.birth_date, u.created_at, \
                au.email \
         FROM upd u JOIN app_user au ON au.id = u.app_user_id",
    )
    .bind(body.first_name.as_deref())
    .bind(body.last_name.as_deref())
    .bind(body.phone.as_deref())
    .bind(&delta)
    .bind(claims.account_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let new_first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let new_last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let new_phone: Option<String> = row.try_get("phone").map_err(|_| AppError::Internal)?;

    let mut diff = serde_json::Map::new();
    if body.first_name.is_some() && new_first_name != old_first_name {
        diff.insert(
            "first_name".into(),
            json!({"old": old_first_name, "new": new_first_name}),
        );
    }
    if body.last_name.is_some() && new_last_name != old_last_name {
        diff.insert(
            "last_name".into(),
            json!({"old": old_last_name, "new": new_last_name}),
        );
    }
    if body.phone.is_some() && new_phone != old_phone {
        diff.insert("phone".into(), json!({"old": old_phone, "new": new_phone}));
    }
    if body.address.is_some() {
        diff.insert("address".into(), json!("updated"));
    }

    // Audit log : entité plateforme → nil UUID comme sentinel cabinet_id.
    // SET LOCAL scoped à la transaction (requis par la policy RLS WITH CHECK d'audit_log).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'update', 'patient_account', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(Value::Object(diff))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let created_at: chrono::DateTime<chrono::Utc> =
        row.try_get("created_at").map_err(|_| AppError::Internal)?;
    let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        user_id = %claims.sub,
        "patient account updated"
    );

    Ok(Json(AccountResponse {
        id,
        first_name: new_first_name,
        last_name: new_last_name,
        email,
        phone: new_phone,
        birth_date: birth_date.map(|d| d.to_string()),
        created_at: created_at.to_rfc3339(),
    }))
}

/// Réponse de `GET /v1/account/coverage`.
#[derive(Serialize)]
pub struct CoverageResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub regime_obligatoire: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub nss_masked: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub amc: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub numero_adherent: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub plateforme: Option<String>,
    pub tiers_payant: bool,
}

/// Masque un NSS : conserve sexe, année, mois + 2 derniers chiffres.
/// Entrée : chaîne quelconque (espaces tolérés). Retourne `None` si < 13 chiffres.
/// Exemple : "291037511607805" → "2 91 03 …05"
fn mask_nss(raw: &str) -> Option<String> {
    let digits: String = raw.chars().filter(|c| c.is_ascii_digit()).collect();
    if digits.len() < 13 {
        return None;
    }
    let last2 = &digits[digits.len() - 2..];
    Some(format!(
        "{} {} {} …{}",
        &digits[0..1],
        &digits[1..3],
        &digits[3..5],
        last2
    ))
}

/// `GET /v1/account/coverage` — retourne la couverture santé du patient.
///
/// `nss_encrypted` est déchiffré en mémoire et masqué avant sérialisation (`05` §10.1) :
/// le numéro de sécurité sociale n'apparaît jamais en clair dans la réponse.
/// Si aucune ligne dans `patient_coverage` → `200 { tiers_payant: false }`.
/// RLS scoped par `app.patient_account_id` (migration 0023).
///
/// Note KMS : le déchiffrement réel arrive avec NUB-T3. En attendant, les bytes sont
/// lus comme UTF-8 plaintext (dev / seed uniquement).
pub async fn get_account_coverage(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<CoverageResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT regime_obligatoire, nss_encrypted, amc, numero_adherent, plateforme, tiers_payant \
         FROM patient_coverage \
         WHERE patient_account_id = $1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        tracing::info!(account_id = %claims.account_id, "patient coverage: no row");
        return Ok(Json(CoverageResponse {
            regime_obligatoire: None,
            nss_masked: None,
            amc: None,
            numero_adherent: None,
            plateforme: None,
            tiers_payant: false,
        }));
    };

    let regime_obligatoire: Option<String> = row
        .try_get("regime_obligatoire")
        .map_err(|_| AppError::Internal)?;
    let nss_encrypted: Option<Vec<u8>> = row
        .try_get("nss_encrypted")
        .map_err(|_| AppError::Internal)?;
    let amc: Option<String> = row.try_get("amc").map_err(|_| AppError::Internal)?;
    let numero_adherent: Option<String> = row
        .try_get("numero_adherent")
        .map_err(|_| AppError::Internal)?;
    let plateforme: Option<String> = row.try_get("plateforme").map_err(|_| AppError::Internal)?;
    let tiers_payant: bool = row
        .try_get("tiers_payant")
        .map_err(|_| AppError::Internal)?;

    let nss_masked = nss_encrypted
        .as_deref()
        .and_then(|b| std::str::from_utf8(b).ok())
        .and_then(mask_nss);

    tracing::info!(account_id = %claims.account_id, "patient coverage queried");

    Ok(Json(CoverageResponse {
        regime_obligatoire,
        nss_masked,
        amc,
        numero_adherent,
        plateforme,
        tiers_payant,
    }))
}

/// Sous-corps mutuelle pour `PATCH /v1/account/coverage`.
#[derive(Deserialize)]
pub struct PatchCoverageMutuelle {
    amc: String,
    numero_adherent: String,
    plateforme: Option<String>,
}

/// Corps de la requête `PATCH /v1/account/coverage`.
#[derive(Deserialize)]
pub struct PatchCoverageBody {
    regime_obligatoire: Option<String>,
    nss: Option<String>,
    mutuelle: Option<PatchCoverageMutuelle>,
    tiers_payant: Option<bool>,
}

/// `PATCH /v1/account/coverage` — met à jour la couverture santé du patient (partiel, audité).
///
/// `nss` est converti en `Vec<u8>` avant stockage (`nss_encrypted` BYTEA) — jamais de NSS
/// en clair en base (`05` §10.1). Note KMS : chiffrement AES-256-GCM réel à partir de NUB-T3 ;
/// en dev/test les octets UTF-8 sont stockés directement.
/// Upsert `ON CONFLICT (patient_account_id)` : création ou mise à jour atomique.
/// Champs absents du body = valeurs existantes conservées (COALESCE / CASE).
/// Réponse `200` avec coverage mise à jour (nss masqué via `mask_nss`).
pub async fn patch_account_coverage(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PatchCoverageBody>,
) -> Result<Json<CoverageResponse>, AppError> {
    if let Some(ref regime) = body.regime_obligatoire {
        if !["regime_general", "ame", "css"].contains(&regime.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    // dev/test : bytes UTF-8 du NSS plaintext (KMS AES-256-GCM à partir de NUB-T3).
    let nss_encrypted: Option<Vec<u8>> = body.nss.as_deref().map(|s| s.as_bytes().to_vec());

    let (mutuelle_amc, mutuelle_numero, mutuelle_plateforme) = match body.mutuelle {
        Some(m) => (Some(m.amc), Some(m.numero_adherent), m.plateforme),
        None => (None, None, None),
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO patient_coverage \
           (patient_account_id, regime_obligatoire, nss_encrypted, \
            amc, numero_adherent, plateforme, tiers_payant) \
         VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, false)) \
         ON CONFLICT (patient_account_id) DO UPDATE SET \
           regime_obligatoire = COALESCE($2, patient_coverage.regime_obligatoire), \
           nss_encrypted      = COALESCE($3, patient_coverage.nss_encrypted), \
           amc                = COALESCE($4, patient_coverage.amc), \
           numero_adherent    = COALESCE($5, patient_coverage.numero_adherent), \
           plateforme         = COALESCE($6, patient_coverage.plateforme), \
           tiers_payant       = CASE WHEN $7 IS NOT NULL \
                                     THEN $7 \
                                     ELSE patient_coverage.tiers_payant END, \
           updated_at         = now() \
         RETURNING regime_obligatoire, nss_encrypted, amc, numero_adherent, plateforme, tiers_payant",
    )
    .bind(claims.account_id)
    .bind(&body.regime_obligatoire)
    .bind(&nss_encrypted)
    .bind(&mutuelle_amc)
    .bind(&mutuelle_numero)
    .bind(&mutuelle_plateforme)
    .bind(body.tiers_payant)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Audit log : entité plateforme → nil UUID comme sentinel cabinet_id.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'update_coverage', 'patient_coverage', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(json!({"regime_obligatoire": body.regime_obligatoire}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let regime_obligatoire: Option<String> = row
        .try_get("regime_obligatoire")
        .map_err(|_| AppError::Internal)?;
    let nss_bytes: Option<Vec<u8>> = row
        .try_get("nss_encrypted")
        .map_err(|_| AppError::Internal)?;
    let amc: Option<String> = row.try_get("amc").map_err(|_| AppError::Internal)?;
    let numero_adherent: Option<String> = row
        .try_get("numero_adherent")
        .map_err(|_| AppError::Internal)?;
    let plateforme: Option<String> = row.try_get("plateforme").map_err(|_| AppError::Internal)?;
    let tiers_payant: bool = row
        .try_get("tiers_payant")
        .map_err(|_| AppError::Internal)?;

    let nss_masked = nss_bytes
        .as_deref()
        .and_then(|b| std::str::from_utf8(b).ok())
        .and_then(mask_nss);

    tracing::info!(
        account_id = %claims.account_id,
        user_id = %claims.sub,
        "patient coverage updated"
    );

    Ok(Json(CoverageResponse {
        regime_obligatoire,
        nss_masked,
        amc,
        numero_adherent,
        plateforme,
        tiers_payant,
    }))
}

/// Réponse de `POST /v1/account/coverage/card`.
#[derive(Serialize)]
pub struct CoverageCardResponse {
    document_id: Uuid,
}

/// `POST /v1/account/coverage/card` — upload de la carte mutuelle (multipart).
///
/// Champs multipart attendus :
/// - `side` : `"recto"` ou `"verso"` (enum strict → `422` sinon).
/// - `file` : JPEG / PNG / PDF ≤ 5 Mo (`image/jpeg`, `image/png`, `application/pdf`).
///
/// Le fichier est scanné (stub → `scan_status = 'pending'`) et inséré dans
/// `document` (`category = 'carte_mutuelle'`).
/// Chiffrement au repos : stub UTF-8 en dev — AES-256-GCM KMS à NUB-T3 (ADR-009).
/// Réponse : `201 { document_id }`.
pub async fn post_coverage_card(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<CoverageCardResponse>), AppError> {
    const MAX_SIZE: usize = 5 * 1024 * 1024;
    const ALLOWED_MIMES: &[&str] = &["image/jpeg", "image/png", "application/pdf"];

    let mut side: Option<String> = None;
    let mut filename: Option<String> = None;
    let mut file_mime: Option<String> = None;
    let mut file_bytes: Option<Vec<u8>> = None;

    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|_| AppError::ValidationError)?
    {
        let name = field.name().unwrap_or("").to_string();
        match name.as_str() {
            "side" => {
                let val = field.text().await.map_err(|_| AppError::ValidationError)?;
                if val != "recto" && val != "verso" {
                    return Err(AppError::ValidationError);
                }
                side = Some(val);
            }
            "file" => {
                let ct = field
                    .content_type()
                    .map(|s| s.to_string())
                    .unwrap_or_default();
                // Extraire le base MIME (avant un éventuel "; charset=…")
                let base_ct = ct.split(';').next().unwrap_or("").trim().to_string();
                if !ALLOWED_MIMES.contains(&base_ct.as_str()) {
                    return Err(AppError::ValidationError);
                }
                file_mime = Some(base_ct);
                filename = field.file_name().map(|s| s.to_string());
                let bytes = field.bytes().await.map_err(|_| AppError::ValidationError)?;
                if bytes.len() > MAX_SIZE {
                    return Err(AppError::ValidationError);
                }
                file_bytes = Some(bytes.to_vec());
            }
            _ => {}
        }
    }

    let side = side.ok_or(AppError::ValidationError)?;
    let file_bytes = file_bytes.ok_or(AppError::ValidationError)?;
    let file_mime = file_mime.ok_or(AppError::ValidationError)?;
    let fname = filename.unwrap_or_else(|| format!("carte_mutuelle_{}.bin", side));
    // Stub : clé Object Storage (chiffrement AES-256-GCM KMS à NUB-T3 — ADR-009).
    let storage_key = Uuid::new_v4().to_string();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO document \
         (patient_account_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, side, uploaded_by) \
         VALUES ($1, 'carte_mutuelle', $2, $3, $4, \
                 encode(digest($5, 'sha256'), 'hex'), 'pending', $6, $7) \
         RETURNING id",
    )
    .bind(claims.account_id)
    .bind(&storage_key)
    .bind(&fname)
    .bind(&file_mime)
    .bind(&file_bytes)
    .bind(&side)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let document_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        document_id = %document_id,
        side = %side,
        "carte mutuelle uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(CoverageCardResponse { document_id }),
    ))
}

/// Un consentement RGPD tel que retourné par `GET /v1/account/consents`.
#[derive(Serialize)]
pub struct ConsentItem {
    purpose: String,
    granted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    granted_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    revoked_at: Option<String>,
}

/// `GET /v1/account/consents` — liste les consentements RGPD du patient courant.
///
/// Lecture seule. Scoped par `app_user_id = claims.sub` (pas de RLS cabinet —
/// `consent_record` est plateforme-level depuis la migration 0017).
pub async fn get_account_consents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<Vec<ConsentItem>>, AppError> {
    let rows = sqlx::query(
        "SELECT purpose, granted, granted_at, revoked_at \
         FROM consent_record \
         WHERE app_user_id = $1 \
         ORDER BY created_at ASC",
    )
    .bind(claims.sub)
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let consents = rows
        .into_iter()
        .map(|row| {
            let purpose: String = row.try_get("purpose").map_err(|_| AppError::Internal)?;
            let granted: bool = row.try_get("granted").map_err(|_| AppError::Internal)?;
            let granted_at: Option<chrono::DateTime<chrono::Utc>> =
                row.try_get("granted_at").map_err(|_| AppError::Internal)?;
            let revoked_at: Option<chrono::DateTime<chrono::Utc>> =
                row.try_get("revoked_at").map_err(|_| AppError::Internal)?;
            Ok(ConsentItem {
                purpose,
                granted,
                granted_at: granted_at.map(|t| t.to_rfc3339()),
                revoked_at: revoked_at.map(|t| t.to_rfc3339()),
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        user_id = %claims.sub,
        count = consents.len(),
        "patient consents listed"
    );

    Ok(Json(consents))
}

/// `POST /v1/pro/verification` — soumet un RPPS ou ADELI à la vérification ANS.
///
/// Crée `provider_verification(status=pending)` et enfile `VerifyProviderJob`.
/// Un seul enregistrement `pending` autorisé par provider (`07` §4.7) : renvoie
/// `409 verification_pending` si un enregistrement pending existe déjà.
pub async fn pro_verification(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: ProAdminClaims,
    Json(body): Json<ProVerificationBody>,
) -> Result<(StatusCode, Json<ProVerificationResponse>), AppError> {
    if body.id_type != "rpps" && body.id_type != "adeli" {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Pose le contexte tenant (SET LOCAL) pour que les policies RLS provider s'appliquent.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let provider_row =
        sqlx::query("SELECT id FROM provider WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::Internal)?;
    let provider_id: Uuid = provider_row.try_get(0).map_err(|_| AppError::Internal)?;

    // Règle métier : un seul pending par provider (§07 §4.7).
    let pending_count: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM provider_verification \
         WHERE provider_id = $1 AND status = 'pending'",
    )
    .bind(provider_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if pending_count > 0 {
        return Err(AppError::Conflict);
    }

    let verification_row = sqlx::query(
        "INSERT INTO provider_verification (provider_id, identifier, id_type) \
         VALUES ($1, $2, $3) RETURNING id",
    )
    .bind(provider_id)
    .bind(&body.identifier)
    .bind(&body.id_type)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let verification_id: Uuid = verification_row
        .try_get(0)
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Enfile le job de vérification ANS (worker hors scope de cette issue).
    dispatcher.enqueue_verify_provider(verification_id);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        provider_id = %provider_id,
        verification_id = %verification_id,
        "provider verification submitted"
    );

    Ok((
        StatusCode::ACCEPTED,
        Json(ProVerificationResponse {
            verification_id,
            status: "pending".to_string(),
        }),
    ))
}
