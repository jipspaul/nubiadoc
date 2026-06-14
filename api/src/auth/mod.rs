//! Handlers d'authentification (routes publiques `/v1/auth/*`).

pub mod forgot_password;
pub mod login;
pub mod logout;
pub mod mfa_enroll;
pub mod mfa_verify;
pub mod refresh;
pub mod register;
pub mod reset_password;
pub mod select_context;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
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
use uuid::Uuid;

use crate::{AppState, JobDispatcher, StorageClient};

/// Réponse de `POST /v1/auth/login`.
#[derive(Serialize)]
pub struct LoginResponse {
    access_token: String,
    refresh_token: String,
    token_type: String,
    expires_in: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    context_required: Option<bool>,
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

/// Claims JWT émis par `POST /v1/pro/register` — porte `cabinet_id` + `role` + `secretariat_id` optionnel.
#[derive(Serialize, Deserialize)]
pub(crate) struct ProRegisterClaims {
    sub: Uuid,
    kind: String,
    cabinet_id: Uuid,
    role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    secretariat_id: Option<Uuid>,
    exp: u64,
}

#[derive(Serialize)]
struct PatientClaims {
    sub: Uuid,
    kind: String,
    account_id: Uuid,
    exp: u64,
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
    Conflict,
    NotFound,
    ProviderNotVerified,
    MemberAlreadyExists,
    SlotTaken,
    GuardianshipRequired,
    InvalidStatus,
    OutOfWindow,
    TooLate,
    LinkExpired,
    HoldInvalid,
    TooManyRequests,
    MissingIdempotencyKey,
    AppointmentNotHonored,
    ReviewAlreadyExists,
    AlreadyOnWaitingList,
    NoActiveMembership,
    LastAdminCannotBeRemoved,
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
            AppError::SlotTaken => {
                (StatusCode::CONFLICT, Json(json!({"code": "slot_taken"}))).into_response()
            }
            AppError::GuardianshipRequired => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "guardianship_required"})),
            )
                .into_response(),
            AppError::InvalidStatus => (
                StatusCode::CONFLICT,
                Json(json!({"error": "invalid_status"})),
            )
                .into_response(),
            AppError::OutOfWindow => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"error": "out_of_window"})),
            )
                .into_response(),
            AppError::TooLate => {
                (StatusCode::CONFLICT, Json(json!({"error": "too_late"}))).into_response()
            }
            AppError::LinkExpired => {
                (StatusCode::GONE, Json(json!({"code": "link_expired"}))).into_response()
            }
            AppError::HoldInvalid => {
                (StatusCode::CONFLICT, Json(json!({"code": "hold_invalid"}))).into_response()
            }
            AppError::TooManyRequests => (
                StatusCode::TOO_MANY_REQUESTS,
                Json(json!({"code": "too_many_requests"})),
            )
                .into_response(),
            AppError::MissingIdempotencyKey => (
                StatusCode::BAD_REQUEST,
                Json(json!({"code": "missing_idempotency_key"})),
            )
                .into_response(),
            AppError::AppointmentNotHonored => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "appointment_not_honored"})),
            )
                .into_response(),
            AppError::ReviewAlreadyExists => (
                StatusCode::CONFLICT,
                Json(json!({"code": "review_already_exists"})),
            )
                .into_response(),
            AppError::AlreadyOnWaitingList => (
                StatusCode::CONFLICT,
                Json(json!({"code": "already_on_waiting_list"})),
            )
                .into_response(),
            AppError::NoActiveMembership => (
                StatusCode::FORBIDDEN,
                Json(json!({"error": "no_active_membership"})),
            )
                .into_response(),
            AppError::LastAdminCannotBeRemoved => (
                StatusCode::CONFLICT,
                Json(json!({"code": "last_admin_cannot_be_removed"})),
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
        validation.leeway = 0;

        let data =
            decode::<ProClaims>(token, &key, &validation).map_err(|_| AppError::Unauthorized)?;

        if data.claims.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        Ok(data.claims)
    }
}

/// Claims JWT pour `GET /v1/me` — accepte patient et pro, extrait `kind`, `account_id`.
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
    #[serde(skip_serializing_if = "Option::is_none")]
    secretariat_id: Option<Uuid>,
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
/// Pour les tokens pro portant un `cabinet_id` (émis par `POST /v1/pro/register`),
/// interroge `cabinet_membership` via RLS (SET LOCAL). Pour les tokens pro sans
/// `cabinet_id` (émis par `POST /v1/auth/login`), `memberships` est vide.
/// Toujours auditée (`read_profile` sur `app_user`, cabinet_id nil UUID sentinel).
pub async fn me(
    State(state): State<AppState>,
    claims: MeClaims,
) -> Result<Json<MeResponse>, AppError> {
    // user_self_select exige app.current_user_id : on le pose en SET LOCAL.
    let mut etx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *etx)
        .await
        .map_err(|_| AppError::Internal)?;
    let row = sqlx::query("SELECT email FROM app_user WHERE id = $1")
        .bind(claims.sub)
        .fetch_one(&mut *etx)
        .await
        .map_err(|_| AppError::Internal)?;
    etx.commit().await.map_err(|_| AppError::Internal)?;

    let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;

    // Pour les tokens pro (login ou register), retourne tous les memberships actifs
    // via user_all_memberships() (SECURITY DEFINER — contourne la RLS cabinet-scoped).
    let memberships = if claims.kind == "pro" {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(claims.sub.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let rows =
            sqlx::query("SELECT cabinet_id, role, secretariat_id FROM user_all_memberships($1)")
                .bind(claims.sub)
                .fetch_all(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;
        rows.into_iter()
            .map(|r| {
                let cid: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
                let secretariat_id: Option<Uuid> = r
                    .try_get("secretariat_id")
                    .map_err(|_| AppError::Internal)?;
                Ok(CabinetMembership {
                    cabinet_id: cid,
                    role,
                    secretariat_id,
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?
    } else {
        vec![]
    };

    // Audit log : entité plateforme → nil UUID comme sentinel cabinet_id.
    let mut atx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *atx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, $3, 'read_profile', 'app_user', $4, $5)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(&claims.kind)
    .bind(claims.sub)
    .bind(json!({}))
    .execute(&mut *atx)
    .await
    .map_err(|_| AppError::Internal)?;
    atx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        kind = %claims.kind,
        "profile read"
    );

    Ok(Json(MeResponse {
        user_id: claims.sub,
        email,
        kind: claims.kind,
        account_id: claims.account_id,
        memberships,
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

    // Pre-generate UUIDs so we can avoid RETURNING on RLS-protected tables.
    // app_user has FORCE RLS (migration 0045): RETURNING id would be blocked by the
    // user_self_select policy (requires app.current_user_id = id, not yet set at insert time).
    // cabinet has FORCE RLS: WITH CHECK requires id = current_setting('app.current_cabinet_id').
    let user_id = Uuid::new_v4();
    let cabinet_id = Uuid::new_v4();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Insert app_user with explicit id — no RETURNING needed (we already know user_id).
    sqlx::query("INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')")
        .bind(user_id)
        .bind(&body.email)
        .bind(&password_hash)
        .execute(&mut *tx)
        .await
        .map_err(|e| {
            if is_unique_violation(&e) {
                AppError::EmailTaken
            } else {
                AppError::Internal
            }
        })?;

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
        secretariat_id: None,
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
    pub(crate) sub: Uuid,
    kind: String,
    /// `cabinet_id` porté par le token (jamais du body/query — invariant tenancy).
    pub(crate) cabinet_id: Uuid,
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

/// Claims JWT pro avec rôle `admin` ou `manager` — pour R13 (provisionnement secrétaire).
///
/// Renvoie `403` si le rôle est `secretary` ou `practitioner`.
#[derive(Debug, Deserialize)]
pub(crate) struct ProAdminOrManagerClaims {
    pub(crate) sub: Uuid,
    kind: String,
    pub(crate) cabinet_id: Uuid,
    role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for ProAdminOrManagerClaims {
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

        let claims = decode::<ProAdminOrManagerClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.kind != "pro" {
            return Err(AppError::Forbidden);
        }
        if claims.role != "admin" && claims.role != "manager" {
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
    pub(crate) sub: Uuid,
    pub(crate) cabinet_id: Uuid,
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

        // Première passe : extrait `kind` pour renvoyer 403 (pas 401)
        // si le token est valide mais n'appartient pas à un pro (ex. token patient).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pro obligatoires (cabinet_id, role).
        let claims = decode::<ProPractitionerClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.role == "secretary" {
            return Err(AppError::Forbidden);
        }

        Ok(claims)
    }
}

/// Claims JWT pro avec accès secrétariat+ (secretary, practitioner, admin).
///
/// Renvoie `401` si absent/invalide, `403` si `kind != "pro"`.
/// `role` est exposé pour le cloisonnement clinique R.4127-72 (motif admin vs clinique).
/// `secretariat_id` présent uniquement pour les secrétaires (R10 : filtrage scope secrétariat).
#[derive(Debug, Deserialize)]
pub(crate) struct ProSecretaryPlusClaims {
    pub(crate) sub: Uuid,
    pub(crate) cabinet_id: Uuid,
    pub(crate) role: String,
    #[serde(default)]
    pub(crate) secretariat_id: Option<Uuid>,
}

#[async_trait]
impl FromRequestParts<AppState> for ProSecretaryPlusClaims {
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

        // Première passe : extrait uniquement `kind` pour renvoyer 403 (pas 401)
        // si le token est valide mais n'appartient pas à un pro (ex. token patient).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pro obligatoires (cabinet_id, role).
        let claims = decode::<ProSecretaryPlusClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

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

    // La RLS user_self_select (migration 0045) bloque le JOIN avec app_user si
    // app.current_user_id ne correspond pas à chaque ligne. On récupère d'abord
    // les membership depuis cabinet_membership (accessible sous la RLS cabinet),
    // puis on pose app.current_user_id pour chaque membre afin de lire son email.
    let cm_rows = sqlx::query(
        "SELECT user_id, role, active, created_at AS joined_at \
         FROM cabinet_membership \
         WHERE cabinet_id = $1 \
         ORDER BY created_at ASC",
    )
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let mut members: Vec<CabinetMemberItem> = Vec::with_capacity(cm_rows.len());
    for row in cm_rows {
        let user_id: Uuid = row.try_get("user_id").map_err(|_| AppError::Internal)?;
        let role: String = row.try_get("role").map_err(|_| AppError::Internal)?;
        let active: bool = row.try_get("active").map_err(|_| AppError::Internal)?;
        let joined_at: chrono::DateTime<chrono::Utc> =
            row.try_get("joined_at").map_err(|_| AppError::Internal)?;

        // Pose current_user_id pour satisfaire user_self_select lors du SELECT email.
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(user_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let email_row = sqlx::query("SELECT email FROM app_user WHERE id = $1")
            .bind(user_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let email = email_row
            .and_then(|r| r.try_get::<String, _>("email").ok())
            .unwrap_or_default();

        members.push(CabinetMemberItem {
            user_id,
            email,
            first_name: None,
            last_name: None,
            role,
            active,
            joined_at: joined_at.to_rfc3339(),
        });
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

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
    claims: ProAdminOrManagerClaims,
    Json(body): Json<PostCabinetMemberBody>,
) -> Result<(StatusCode, Json<CabinetMemberItem>), AppError> {
    if !["practitioner", "secretary", "admin", "manager", "doctor"].contains(&body.role.as_str()) {
        return Err(AppError::ValidationError);
    }

    // Pre-generate user_id so we can insert app_user without RETURNING.
    // RETURNING is blocked by the user_self_select RLS policy (migration 0045):
    // it requires app.current_user_id = id, which is only available for the user's own row.
    // By pre-generating the UUID and setting app.current_user_id before the INSERT,
    // the RLS SELECT policy passes for the newly inserted row.
    //
    // If the email already exists (23505 unique violation), we return MemberAlreadyExists:
    // the app_user SELECT RLS prevents looking up an existing user by email with nubia_app,
    // so inviting a user who already has an account via a different cabinet is not supported
    // in this flow (requires the owner role for the lookup, which is out of scope here).
    let user_id = Uuid::new_v4();

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Set current_user_id to the pre-generated UUID so that the user_self_select policy
    // passes for this new row within the same transaction (used by subsequent SELECT if needed).
    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(user_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Token brut conservé pour l'email d'invite (uniquement si nouveau compte).
    let raw_invite_token = Uuid::new_v4().to_string();

    // INSERT sans RETURNING (RETURNING bloqué par user_self_select quand current_user_id ≠ id).
    // On utilise l'id pré-généré. En cas de violation unique sur email → l'email existe déjà.
    sqlx::query(
        "INSERT INTO app_user \
         (id, email, password_hash, kind, first_name, last_name, \
          password_reset_token, password_reset_expires_at) \
         VALUES ($1, $2, NULL, 'pro', $3, $4, \
                 encode(digest($5, 'sha256'), 'hex'), now() + interval '72 hours')",
    )
    .bind(user_id)
    .bind(&body.email)
    .bind(&body.first_name)
    .bind(&body.last_name)
    .bind(&raw_invite_token)
    .execute(&mut *tx)
    .await
    .map_err(|e| {
        if is_unique_violation(&e) {
            // L'email est déjà utilisé. Sous RLS nubia_app, on ne peut pas résoudre
            // l'UUID de l'utilisateur existant par email → 409 member_already_exists.
            AppError::MemberAlreadyExists
        } else {
            AppError::Internal
        }
    })?;

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

    // Email d'invite envoyé après commit (fire-and-forget — nouveau compte).
    state.mailer.send_invite(&body.email, &raw_invite_token);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %user_id,
        role = %body.role,
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

        // Première passe : extrait `kind` pour renvoyer 403 (pas 401)
        // si le token est valide mais n'appartient pas à un patient (ex. token pro).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "patient" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs patient obligatoires (account_id).
        let claims = decode::<PatientAccountClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

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
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT pa.id, pa.first_name, pa.last_name, pa.phone, pa.birth_date, pa.created_at, \
                au.email \
         FROM patient_account pa \
         JOIN app_user au ON au.id = pa.app_user_id \
         WHERE pa.id = $1 AND pa.app_user_id = $2 AND pa.deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

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

    // Rôles valides pour `cabinet_membership` (cf. CHECK en base : migration
    // 0002). `manager` est un rôle de secrétariat, pas de cabinet ; le rôle
    // praticien s'appelle `practitioner` (pas `doctor`).
    if let Some(ref role) = body.role {
        if !["admin", "practitioner", "secretary"].contains(&role.as_str()) {
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

    // Bloque la suppression du dernier admin actif du cabinet → 409.
    let admin_count_row = sqlx::query(
        "SELECT COUNT(*) AS cnt FROM cabinet_membership \
         WHERE cabinet_id = $1 AND role = 'admin' AND active = true",
    )
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let admin_count: i64 = admin_count_row
        .try_get("cnt")
        .map_err(|_| AppError::Internal)?;

    let target_role_row = sqlx::query(
        "SELECT role FROM cabinet_membership \
         WHERE cabinet_id = $1 AND user_id = $2",
    )
    .bind(claims.cabinet_id)
    .bind(target_user_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let target_role: String = target_role_row
        .try_get("role")
        .map_err(|_| AppError::Internal)?;

    if target_role == "admin" && admin_count <= 1 {
        return Err(AppError::LastAdminCannotBeRemoved);
    }

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

    // Validation format E.164 : commence par '+', suivi de 7 à 14 chiffres.
    if let Some(ref phone) = body.phone {
        let digits: &str = phone.strip_prefix('+').unwrap_or("");
        if digits.is_empty()
            || digits.len() < 7
            || digits.len() > 14
            || !digits.chars().all(|c| c.is_ascii_digit())
        {
            return Err(AppError::ValidationError);
        }
    }

    let delta = contact_delta(body.address.as_ref());

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
        .bind(claims.sub.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

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
         VALUES ($1, $2, 'patient', 'update_account', 'patient_account', $3, $4)",
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
    signed_url: String,
}

// Signature EICAR (68 octets) — chaîne standard de test antivirus.
const EICAR_SIGNATURE: &[u8] =
    b"X5O!P%@AP[4\\PZX54(P^)7CC)7}$EICAR-STANDARD-ANTIVIRUS-TEST-FILE!$H+H*";

/// `POST /v1/account/coverage/card` — upload de la carte mutuelle (multipart).
///
/// Champs multipart attendus :
/// - `side` : `"recto"` ou `"verso"` (enum strict → `422` sinon).
/// - `file` : JPEG / PNG / PDF ≤ 10 Mo (`image/jpeg`, `image/png`, `application/pdf`).
///
/// Antivirus : fichier contenant la signature EICAR → `422`.
/// Le fichier est scanné (stub → `scan_status = 'pending'`) et inséré dans
/// `document` (`category = 'carte_mutuelle'`).
/// Chiffrement au repos : stub UTF-8 en dev — AES-256-GCM KMS à NUB-T3 (ADR-009).
/// Réponse : `201 { document_id, signed_url }`.
pub async fn post_coverage_card(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(storage): Extension<Arc<dyn StorageClient>>,
    mut multipart: Multipart,
) -> Result<(StatusCode, Json<CoverageCardResponse>), AppError> {
    const MAX_SIZE: usize = 10 * 1024 * 1024;
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

    // Antivirus : rejet EICAR (stub — intégration ClamAV à NUB-T3).
    if file_bytes
        .windows(EICAR_SIGNATURE.len())
        .any(|w| w == EICAR_SIGNATURE)
    {
        return Err(AppError::ValidationError);
    }

    let fname = filename.unwrap_or_else(|| format!("carte_mutuelle_{}.bin", side));
    let size_bytes = file_bytes.len() as i64;
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
          size_bytes, sha256, scan_status, side, uploaded_by) \
         VALUES ($1, 'carte_mutuelle', $2, $3, $4, $5, \
                 encode(digest($6, 'sha256'), 'hex'), 'pending', $7, $8) \
         RETURNING id",
    )
    .bind(claims.account_id)
    .bind(&storage_key)
    .bind(&fname)
    .bind(&file_mime)
    .bind(size_bytes)
    .bind(&file_bytes)
    .bind(&side)
    .bind(claims.sub)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let document_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    // URL signée valable 15 minutes.
    let signed_url = storage.sign_url(&storage_key, 900);

    tracing::info!(
        account_id = %claims.account_id,
        document_id = %document_id,
        side = %side,
        "carte mutuelle uploaded"
    );

    Ok((
        StatusCode::CREATED,
        Json(CoverageCardResponse {
            document_id,
            signed_url,
        }),
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

/// Corps de la requête `PUT /v1/account/consents/{purpose}`.
#[derive(Deserialize)]
pub struct PutConsentBody {
    granted: bool,
}

/// Réponse de `PUT /v1/account/consents/{purpose}`.
#[derive(Serialize)]
pub struct ConsentUpdateResponse {
    purpose: String,
    granted: bool,
    updated_at: String,
}

/// `PUT /v1/account/consents/{purpose}` — donne ou révoque un consentement RGPD.
///
/// Upsert idempotent : `granted_at` posé si accordé, `revoked_at` si révoqué.
/// Chaque changement est audité dans `audit_log` (§07 §3.2).
pub async fn put_account_consent(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(purpose): Path<String>,
    Json(body): Json<PutConsentBody>,
) -> Result<Json<ConsentUpdateResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO consent_record (patient_account_id, app_user_id, purpose, granted, granted_at, revoked_at)
         VALUES ($1, $2, $3, $4,
                 CASE WHEN $4 THEN now() ELSE NULL END,
                 CASE WHEN NOT $4 THEN now() ELSE NULL END)
         ON CONFLICT (patient_account_id, purpose) DO UPDATE SET
           granted    = EXCLUDED.granted,
           granted_at = CASE WHEN EXCLUDED.granted THEN now()
                              ELSE consent_record.granted_at END,
           revoked_at = CASE WHEN NOT EXCLUDED.granted THEN now() ELSE NULL END
         RETURNING purpose, granted,
                   COALESCE(revoked_at, granted_at, created_at) AS updated_at",
    )
    .bind(claims.account_id)
    .bind(claims.sub)
    .bind(&purpose)
    .bind(body.granted)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Audit log (§07 §3.2) — nil UUID comme sentinel cabinet_id (entité plateforme).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'update_consent', 'consent_record', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(json!({"purpose": purpose, "granted": body.granted}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let purpose_out: String = row.try_get("purpose").map_err(|_| AppError::Internal)?;
    let granted_out: bool = row.try_get("granted").map_err(|_| AppError::Internal)?;
    let updated_at: chrono::DateTime<chrono::Utc> =
        row.try_get("updated_at").map_err(|_| AppError::Internal)?;

    tracing::info!(
        user_id = %claims.sub,
        purpose = %purpose_out,
        granted = granted_out,
        "patient consent updated"
    );

    Ok(Json(ConsentUpdateResponse {
        purpose: purpose_out,
        granted: granted_out,
        updated_at: updated_at.to_rfc3339(),
    }))
}

/// Corps de la requête `PATCH /v1/account/notification-preferences`.
#[derive(Deserialize)]
pub struct PatchNotificationPreferencesBody {
    email_rdv: Option<bool>,
    sms_rdv: Option<bool>,
    push_rdv: Option<bool>,
    email_messagerie: Option<bool>,
    push_messagerie: Option<bool>,
    email_rappels: Option<bool>,
    push_rappels: Option<bool>,
}

/// Réponse de `GET /v1/account/notification-preferences`.
#[derive(Serialize)]
pub struct NotificationPreferenceResponse {
    email_rdv: bool,
    sms_rdv: bool,
    push_rdv: bool,
    email_messagerie: bool,
    push_messagerie: bool,
    email_rappels: bool,
    push_rappels: bool,
}

/// `GET /v1/account/notification-preferences` — retourne les préférences de notification du patient.
///
/// Si aucune ligne dans `notification_preference` → retourne les défauts (tous `true`).
/// RLS scoped par `app.current_account_id` (migration 0049).
pub async fn get_account_notification_preferences(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<NotificationPreferenceResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT email_rdv, sms_rdv, push_rdv, \
                email_messagerie, push_messagerie, \
                email_rappels, push_rappels \
         FROM notification_preference \
         WHERE patient_account_id = $1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let prefs = match row {
        None => NotificationPreferenceResponse {
            email_rdv: true,
            sms_rdv: true,
            push_rdv: true,
            email_messagerie: true,
            push_messagerie: true,
            email_rappels: true,
            push_rappels: true,
        },
        Some(r) => NotificationPreferenceResponse {
            email_rdv: r.try_get("email_rdv").map_err(|_| AppError::Internal)?,
            sms_rdv: r.try_get("sms_rdv").map_err(|_| AppError::Internal)?,
            push_rdv: r.try_get("push_rdv").map_err(|_| AppError::Internal)?,
            email_messagerie: r
                .try_get("email_messagerie")
                .map_err(|_| AppError::Internal)?,
            push_messagerie: r
                .try_get("push_messagerie")
                .map_err(|_| AppError::Internal)?,
            email_rappels: r.try_get("email_rappels").map_err(|_| AppError::Internal)?,
            push_rappels: r.try_get("push_rappels").map_err(|_| AppError::Internal)?,
        },
    };

    tracing::info!(
        account_id = %claims.account_id,
        "notification preferences queried"
    );

    Ok(Json(prefs))
}

/// `PATCH /v1/account/notification-preferences` — met à jour partiellement les opt-in de notification.
///
/// Upsert idempotent : seuls les champs présents dans le body sont modifiés.
/// Champs absents → valeur existante conservée (CASE WHEN) ; défaut `true` à la création.
/// RLS scoped par `app.current_account_id` (migration 0049).
pub async fn patch_account_notification_preferences(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PatchNotificationPreferencesBody>,
) -> Result<Json<NotificationPreferenceResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO notification_preference \
           (patient_account_id, email_rdv, sms_rdv, push_rdv, \
            email_messagerie, push_messagerie, email_rappels, push_rappels) \
         VALUES ($1, \
           COALESCE($2, true), COALESCE($3, true), COALESCE($4, true), \
           COALESCE($5, true), COALESCE($6, true), COALESCE($7, true), COALESCE($8, true)) \
         ON CONFLICT (patient_account_id, channel, type) DO UPDATE SET \
           email_rdv        = CASE WHEN $2 IS NOT NULL THEN $2 \
                                   ELSE notification_preference.email_rdv END, \
           sms_rdv          = CASE WHEN $3 IS NOT NULL THEN $3 \
                                   ELSE notification_preference.sms_rdv END, \
           push_rdv         = CASE WHEN $4 IS NOT NULL THEN $4 \
                                   ELSE notification_preference.push_rdv END, \
           email_messagerie = CASE WHEN $5 IS NOT NULL THEN $5 \
                                   ELSE notification_preference.email_messagerie END, \
           push_messagerie  = CASE WHEN $6 IS NOT NULL THEN $6 \
                                   ELSE notification_preference.push_messagerie END, \
           email_rappels    = CASE WHEN $7 IS NOT NULL THEN $7 \
                                   ELSE notification_preference.email_rappels END, \
           push_rappels     = CASE WHEN $8 IS NOT NULL THEN $8 \
                                   ELSE notification_preference.push_rappels END, \
           updated_at       = now() \
         RETURNING email_rdv, sms_rdv, push_rdv, \
                   email_messagerie, push_messagerie, \
                   email_rappels, push_rappels",
    )
    .bind(claims.account_id)
    .bind(body.email_rdv)
    .bind(body.sms_rdv)
    .bind(body.push_rdv)
    .bind(body.email_messagerie)
    .bind(body.push_messagerie)
    .bind(body.email_rappels)
    .bind(body.push_rappels)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        "notification preferences updated"
    );

    Ok(Json(NotificationPreferenceResponse {
        email_rdv: row.try_get("email_rdv").map_err(|_| AppError::Internal)?,
        sms_rdv: row.try_get("sms_rdv").map_err(|_| AppError::Internal)?,
        push_rdv: row.try_get("push_rdv").map_err(|_| AppError::Internal)?,
        email_messagerie: row
            .try_get("email_messagerie")
            .map_err(|_| AppError::Internal)?,
        push_messagerie: row
            .try_get("push_messagerie")
            .map_err(|_| AppError::Internal)?,
        email_rappels: row
            .try_get("email_rappels")
            .map_err(|_| AppError::Internal)?,
        push_rappels: row
            .try_get("push_rappels")
            .map_err(|_| AppError::Internal)?,
    }))
}

/// `GET /v1/account/consents` — liste les consentements RGPD du patient courant.
///
/// Lecture seule. Scoped par `patient_account_id = claims.account_id`.
/// RLS scoped par `app.current_account_id` (migration 0048).
pub async fn get_account_consents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<Vec<ConsentItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT purpose, granted, granted_at, revoked_at \
         FROM consent_record \
         WHERE patient_account_id = $1 \
         ORDER BY created_at ASC",
    )
    .bind(claims.account_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

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

/// Un proche/ayant droit tel que retourné par `GET /v1/account/dependents`.
#[derive(Serialize)]
pub struct DependentItem {
    dependent_account_id: Uuid,
    first_name: String,
    last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    birth_date: Option<String>,
    relationship: String,
}

/// `GET /v1/account/dependents` — liste les proches/ayants droit actifs du patient.
///
/// Retourne les lignes `account_guardianship` actives où `guardian_account_id = moi`.
/// RLS scoped par `app.current_account_id` (migration 0025).
pub async fn get_account_dependents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<Vec<DependentItem>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT ag.dependent_account_id, pa.first_name, pa.last_name, pa.birth_date, \
                ag.relationship \
         FROM account_guardianship ag \
         JOIN patient_account pa ON pa.id = ag.dependent_account_id \
         WHERE ag.guardian_account_id = $1 AND ag.active = true \
         ORDER BY pa.last_name ASC, pa.first_name ASC",
    )
    .bind(claims.account_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let dependents = rows
        .into_iter()
        .map(|row| {
            let dependent_account_id: Uuid = row
                .try_get("dependent_account_id")
                .map_err(|_| AppError::Internal)?;
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            let birth_date: Option<chrono::NaiveDate> =
                row.try_get("birth_date").map_err(|_| AppError::Internal)?;
            let relationship: String = row
                .try_get("relationship")
                .map_err(|_| AppError::Internal)?;
            Ok(DependentItem {
                dependent_account_id,
                first_name,
                last_name,
                birth_date: birth_date.map(|d| d.to_string()),
                relationship,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        account_id = %claims.account_id,
        count = dependents.len(),
        "patient dependents listed"
    );

    Ok(Json(dependents))
}

/// Réponse de `GET /v1/account/dependents/{id}`.
#[derive(Serialize)]
pub struct DependentDetailResponse {
    dependent_account_id: Uuid,
    first_name: String,
    last_name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    birth_date: Option<String>,
    relationship: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    coverage: Option<CoverageResponse>,
}

/// `GET /v1/account/dependents/{id}` — profil détaillé d'un proche.
///
/// Vérifie que `account_guardianship.guardian_account_id = claims.account_id AND active = true`.
/// Proche inconnu ou hors tutelle → `404` (anti-énumération, §07 §2.9).
/// Accès audité : `action:'read_dependent', entity:'patient_account'`.
pub async fn get_account_dependent_by_id(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(dependent_id): Path<Uuid>,
) -> Result<Json<DependentDetailResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT ag.dependent_account_id, pa.first_name, pa.last_name, pa.birth_date, \
                ag.relationship \
         FROM account_guardianship ag \
         JOIN patient_account pa ON pa.id = ag.dependent_account_id \
         WHERE ag.guardian_account_id = $1 AND ag.dependent_account_id = $2 AND ag.active = true",
    )
    .bind(claims.account_id)
    .bind(dependent_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let dependent_account_id: Uuid = row
        .try_get("dependent_account_id")
        .map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let relationship: String = row
        .try_get("relationship")
        .map_err(|_| AppError::Internal)?;

    // Couverture du proche — RLS scoped par app.patient_account_id (migration 0023).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(dependent_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cov_row = sqlx::query(
        "SELECT regime_obligatoire, nss_encrypted, amc, numero_adherent, plateforme, tiers_payant \
         FROM patient_coverage \
         WHERE patient_account_id = $1",
    )
    .bind(dependent_account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let coverage = cov_row
        .map(|r| -> Result<CoverageResponse, AppError> {
            let regime_obligatoire: Option<String> = r
                .try_get("regime_obligatoire")
                .map_err(|_| AppError::Internal)?;
            let nss_encrypted: Option<Vec<u8>> =
                r.try_get("nss_encrypted").map_err(|_| AppError::Internal)?;
            let amc: Option<String> = r.try_get("amc").map_err(|_| AppError::Internal)?;
            let numero_adherent: Option<String> = r
                .try_get("numero_adherent")
                .map_err(|_| AppError::Internal)?;
            let plateforme: Option<String> =
                r.try_get("plateforme").map_err(|_| AppError::Internal)?;
            let tiers_payant: bool = r.try_get("tiers_payant").map_err(|_| AppError::Internal)?;
            let nss_masked = nss_encrypted
                .as_deref()
                .and_then(|b| std::str::from_utf8(b).ok())
                .and_then(mask_nss);
            Ok(CoverageResponse {
                regime_obligatoire,
                nss_masked,
                amc,
                numero_adherent,
                plateforme,
                tiers_payant,
            })
        })
        .transpose()?;

    // Audit log (§07 §2.9) — nil UUID comme sentinel cabinet_id (entité plateforme).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'read_dependent', 'patient_account', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(dependent_account_id)
    .bind(json!({}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        dependent_account_id = %dependent_account_id,
        "patient dependent detail queried"
    );

    Ok(Json(DependentDetailResponse {
        dependent_account_id,
        first_name,
        last_name,
        birth_date: birth_date.map(|d| d.to_string()),
        relationship,
        coverage,
    }))
}

/// Corps de la couverture pour `POST /v1/account/dependents`.
#[derive(Deserialize)]
pub struct PostDependentCoverageBody {
    regime_obligatoire: Option<String>,
    nss: Option<String>,
    amc: Option<String>,
    numero_adherent: Option<String>,
}

/// Corps de la requête `POST /v1/account/dependents`.
#[derive(Deserialize)]
pub struct PostDependentBody {
    first_name: String,
    last_name: String,
    birth_date: Option<String>,
    relationship: String,
    coverage: Option<PostDependentCoverageBody>,
}

/// Réponse de `POST /v1/account/dependents`.
#[derive(Serialize)]
pub struct PostDependentResponse {
    dependent_account_id: Uuid,
}

/// `POST /v1/account/dependents` — ajoute un proche/ayant droit.
///
/// Transaction atomique : crée un `app_user` géré (sans mot de passe), un `patient_account`
/// pour le proche, et une ligne `account_guardianship` liant le tuteur.
/// §07 §4.6 : `authority='full'` si `birth_date` < 18 ans (conforme mineurs).
/// Si `coverage` fourni → crée/upsert `patient_coverage` pour le proche.
pub async fn post_account_dependents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PostDependentBody>,
) -> Result<(StatusCode, Json<PostDependentResponse>), AppError> {
    if !["enfant", "conjoint", "parent", "autre"].contains(&body.relationship.as_str()) {
        return Err(AppError::ValidationError);
    }

    let birth_date: Option<chrono::NaiveDate> = match body.birth_date.as_deref() {
        Some(s) => Some(s.parse().map_err(|_| AppError::ValidationError)?),
        None => None,
    };

    // §07 §4.6 : 'full' est imposé pour les mineurs ; c'est aussi la valeur par défaut
    // à la création pour tous les proches (le tuteur a pleine autorité sur le compte géré).
    let authority = "full";

    // Pré-génère les UUIDs pour éviter RETURNING sur tables avec FORCE RLS.
    // app_user (migration 0045) et patient_account ont FORCE RLS : RETURNING id serait
    // bloqué par les policies SELECT (user_self_select / account_self_select).
    let managed_user_id = Uuid::new_v4();
    let dependent_account_id = Uuid::new_v4();

    // Email synthétique unique — le compte géré ne peut pas se connecter directement.
    let managed_email = format!("managed-{}@nubia.internal", managed_user_id);

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // app_user géré : password_hash NULL = aucun accès direct possible.
    sqlx::query("INSERT INTO app_user (id, email, kind) VALUES ($1, $2, 'patient')")
        .bind(managed_user_id)
        .bind(&managed_email)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO patient_account (id, app_user_id, first_name, last_name, birth_date) \
         VALUES ($1, $2, $3, $4, $5)",
    )
    .bind(dependent_account_id)
    .bind(managed_user_id)
    .bind(&body.first_name)
    .bind(&body.last_name)
    .bind(birth_date)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO account_guardianship \
         (guardian_account_id, dependent_account_id, relationship, authority, active) \
         VALUES ($1, $2, $3, $4, true)",
    )
    .bind(claims.account_id)
    .bind(dependent_account_id)
    .bind(&body.relationship)
    .bind(authority)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(cov) = body.coverage {
        // patient_coverage est scopée par app.patient_account_id (migration 0023).
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(dependent_account_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        // dev/test : bytes UTF-8 du NSS plaintext (KMS AES-256-GCM à partir de NUB-T3).
        let nss_encrypted: Option<Vec<u8>> = cov.nss.as_deref().map(|s| s.as_bytes().to_vec());

        sqlx::query(
            "INSERT INTO patient_coverage \
               (patient_account_id, regime_obligatoire, nss_encrypted, amc, numero_adherent) \
             VALUES ($1, $2, $3, $4, $5) \
             ON CONFLICT (patient_account_id) DO UPDATE SET \
               regime_obligatoire = COALESCE($2, patient_coverage.regime_obligatoire), \
               nss_encrypted      = COALESCE($3, patient_coverage.nss_encrypted), \
               amc                = COALESCE($4, patient_coverage.amc), \
               numero_adherent    = COALESCE($5, patient_coverage.numero_adherent), \
               updated_at         = now()",
        )
        .bind(dependent_account_id)
        .bind(&cov.regime_obligatoire)
        .bind(&nss_encrypted)
        .bind(&cov.amc)
        .bind(&cov.numero_adherent)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        guardian_account_id = %claims.account_id,
        dependent_account_id = %dependent_account_id,
        relationship = %body.relationship,
        "dependent account created"
    );

    Ok((
        StatusCode::CREATED,
        Json(PostDependentResponse {
            dependent_account_id,
        }),
    ))
}

/// Corps de la couverture pour `PATCH /v1/account/dependents/{id}`.
#[derive(Deserialize)]
pub struct PatchDependentCoverageBody {
    regime_obligatoire: Option<String>,
    nss: Option<String>,
    amc: Option<String>,
    numero_adherent: Option<String>,
    plateforme: Option<String>,
    tiers_payant: Option<bool>,
}

/// Corps de la requête `PATCH /v1/account/dependents/{id}`.
#[derive(Deserialize)]
pub struct PatchDependentBody {
    first_name: Option<String>,
    last_name: Option<String>,
    birth_date: Option<String>,
    relationship: Option<String>,
    coverage: Option<PatchDependentCoverageBody>,
}

/// `PATCH /v1/account/dependents/{id}` — met à jour les données d'un proche (partiel, audité).
///
/// Vérifie la tutelle active (`account_guardianship`). Champs absents → non modifiés.
/// Si `coverage` présent : upsert `patient_coverage` lié au proche.
/// Champs inconnus dans le body → ignorés (pas de 422, §spec issue #321).
/// Modification auditée : `action:'update_dependent'` (§07 §4.6).
pub async fn patch_account_dependent(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(dependent_id): Path<Uuid>,
    Json(body): Json<PatchDependentBody>,
) -> Result<Json<DependentDetailResponse>, AppError> {
    let birth_date: Option<chrono::NaiveDate> = match body.birth_date.as_deref() {
        Some(s) => Some(s.parse().map_err(|_| AppError::ValidationError)?),
        None => None,
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Vérifie la tutelle active → 404 si introuvable ou inactive (anti-énumération §07 §2.9).
    sqlx::query(
        "SELECT 1 FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(claims.account_id)
    .bind(dependent_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    // Mise à jour des champs identité du proche (COALESCE = non modifié si absent).
    sqlx::query(
        "UPDATE patient_account \
         SET \
           first_name = COALESCE($1, first_name), \
           last_name  = COALESCE($2, last_name), \
           birth_date = COALESCE($3, birth_date), \
           updated_at = now() \
         WHERE id = $4",
    )
    .bind(body.first_name.as_deref())
    .bind(body.last_name.as_deref())
    .bind(birth_date)
    .bind(dependent_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Mise à jour de la relation si fournie.
    if let Some(ref rel) = body.relationship {
        sqlx::query(
            "UPDATE account_guardianship \
             SET relationship = $1, updated_at = now() \
             WHERE guardian_account_id = $2 AND dependent_account_id = $3 AND active = true",
        )
        .bind(rel)
        .bind(claims.account_id)
        .bind(dependent_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    // Upsert de la couverture si présente (RLS scoped par app.patient_account_id).
    if let Some(cov) = body.coverage {
        sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
            .bind(dependent_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        // dev/test : bytes UTF-8 du NSS plaintext (KMS AES-256-GCM à partir de NUB-T3).
        let nss_encrypted: Option<Vec<u8>> = cov.nss.as_deref().map(|s| s.as_bytes().to_vec());

        sqlx::query(
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
               updated_at         = now()",
        )
        .bind(dependent_id)
        .bind(&cov.regime_obligatoire)
        .bind(&nss_encrypted)
        .bind(&cov.amc)
        .bind(&cov.numero_adherent)
        .bind(&cov.plateforme)
        .bind(cov.tiers_payant)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    // Re-lecture des données mises à jour (app.current_account_id encore actif depuis le début).
    let row = sqlx::query(
        "SELECT ag.dependent_account_id, pa.first_name, pa.last_name, pa.birth_date, \
                ag.relationship \
         FROM account_guardianship ag \
         JOIN patient_account pa ON pa.id = ag.dependent_account_id \
         WHERE ag.guardian_account_id = $1 AND ag.dependent_account_id = $2 AND ag.active = true",
    )
    .bind(claims.account_id)
    .bind(dependent_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let dependent_account_id: Uuid = row
        .try_get("dependent_account_id")
        .map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let birth_date_out: Option<chrono::NaiveDate> =
        row.try_get("birth_date").map_err(|_| AppError::Internal)?;
    let relationship: String = row
        .try_get("relationship")
        .map_err(|_| AppError::Internal)?;

    // Couverture mise à jour — RLS scoped par app.patient_account_id (migration 0023).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(dependent_account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cov_row = sqlx::query(
        "SELECT regime_obligatoire, nss_encrypted, amc, numero_adherent, plateforme, tiers_payant \
         FROM patient_coverage \
         WHERE patient_account_id = $1",
    )
    .bind(dependent_account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let coverage = cov_row
        .map(|r| -> Result<CoverageResponse, AppError> {
            let regime_obligatoire: Option<String> = r
                .try_get("regime_obligatoire")
                .map_err(|_| AppError::Internal)?;
            let nss_encrypted: Option<Vec<u8>> =
                r.try_get("nss_encrypted").map_err(|_| AppError::Internal)?;
            let amc: Option<String> = r.try_get("amc").map_err(|_| AppError::Internal)?;
            let numero_adherent: Option<String> = r
                .try_get("numero_adherent")
                .map_err(|_| AppError::Internal)?;
            let plateforme: Option<String> =
                r.try_get("plateforme").map_err(|_| AppError::Internal)?;
            let tiers_payant: bool = r.try_get("tiers_payant").map_err(|_| AppError::Internal)?;
            let nss_masked = nss_encrypted
                .as_deref()
                .and_then(|b| std::str::from_utf8(b).ok())
                .and_then(mask_nss);
            Ok(CoverageResponse {
                regime_obligatoire,
                nss_masked,
                amc,
                numero_adherent,
                plateforme,
                tiers_payant,
            })
        })
        .transpose()?;

    // Audit log (§07 §4.6) — nil UUID comme sentinel cabinet_id (entité plateforme).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'update_dependent', 'patient_account', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(dependent_account_id)
    .bind(json!({}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        dependent_account_id = %dependent_account_id,
        "patient dependent updated"
    );

    Ok(Json(DependentDetailResponse {
        dependent_account_id,
        first_name,
        last_name,
        birth_date: birth_date_out.map(|d| d.to_string()),
        relationship,
        coverage,
    }))
}

/// `DELETE /v1/account/dependents/{id}` — révoque la tutelle sur un proche (soft-delete).
///
/// Met `account_guardianship.active = false` + `updated_at = now()`.
/// Tutelle inexistante ou déjà révoquée → `404` (anti-énumération §07 §2.9).
/// Audité : `action:'revoke_guardianship'` (§07 §10).
pub async fn delete_account_dependent(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(dependent_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // 404 si tutelle introuvable ou déjà révoquée — double DELETE idempotent côté état.
    sqlx::query(
        "SELECT 1 FROM account_guardianship \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(claims.account_id)
    .bind(dependent_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    // Soft-delete uniquement — jamais de DELETE SQL (§07 §10).
    sqlx::query(
        "UPDATE account_guardianship \
         SET active = false, updated_at = now() \
         WHERE guardian_account_id = $1 AND dependent_account_id = $2 AND active = true",
    )
    .bind(claims.account_id)
    .bind(dependent_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Audit log — nil UUID comme sentinel cabinet_id (entité plateforme).
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'revoke_guardianship', 'account_guardianship', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(dependent_id)
    .bind(json!({}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        guardian_account_id = %claims.account_id,
        dependent_account_id = %dependent_id,
        "guardianship revoked"
    );

    Ok(StatusCode::NO_CONTENT)
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
        "INSERT INTO provider_verification (provider_id, cabinet_id, identifier, id_type) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(provider_id)
    .bind(claims.cabinet_id)
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
