//! Handlers d'authentification (routes publiques `/v1/auth/*`).

pub mod forgot_password;
pub mod login;
pub mod logout;
pub mod mfa_crypto;
pub mod mfa_enroll;
pub mod mfa_verify;
pub mod refresh;
pub mod register;
pub mod reset_password;
pub mod select_context;
pub mod select_nurse_context;
pub mod select_pharmacy_context;

use argon2::{
    password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
    Argon2,
};
use async_trait::async_trait;
use axum::{
    extract::{Extension, FromRequestParts, Multipart, Path, State},
    http::{header::RETRY_AFTER, request::Parts, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{Acquire, Row};
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use uuid::Uuid;

use crate::{
    appointments_response::is_exclusion_violation, AppState, JobDispatcher, StorageClient,
};

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
    pub(crate) sub: Uuid,
    /// Type de compte : "pro".
    kind: String,
    exp: u64,
}

/// Erreur HTTP renvoyée au client.
#[derive(Debug)]
pub(crate) enum AppError {
    Unauthorized,
    Unauthenticated,
    MfaRequired,
    ValidationError,
    Internal,
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
    HasBooking,
    OutOfWindow,
    TooEarly,
    TooLate,
    LinkExpired,
    HoldInvalid,
    TooManyRequests(u32),
    MissingIdempotencyKey,
    AppointmentNotHonored,
    ReviewAlreadyExists,
    AlreadyOnWaitingList,
    InsufficientStock,
    NoActiveMembership,
    LastAdminCannotBeRemoved,
    StartAtNotFuture,
    InvitationInvalid,
    AlreadyOrdered,
    IdempotencyKeyConflict,
    /// Param de pagination non supporté par cet endpoint (ex: `?page` sur une
    /// liste qui pagine via `limit`/`offset`). Renvoie un 400 explicite plutôt
    /// que d'ignorer silencieusement le paramètre (#3521).
    UnsupportedPageParam,
    /// `?status=` hors de l'énum `quote.status` (CHECK, migration 0006) sur
    /// `GET /v1/cabinet/quotes` — avant, une valeur comme `pending`/`paid`
    /// (boutons factices côté web-console) passait telle quelle dans
    /// `WHERE q.status = $2` et renvoyait silencieusement une liste vide au
    /// lieu d'un 400 (#4066).
    InvalidQuoteStatusFilter,
    /// `?status=` hors de l'énum `appointment.status` (CHECK, migration 0005)
    /// sur `GET /v1/cabinet/appointments` — même lacune que
    /// `InvalidQuoteStatusFilter` (#4066) : une valeur hors énum passait
    /// telle quelle dans `WHERE a.status = $2` et renvoyait silencieusement
    /// une liste vide au lieu d'un 400 (#4420).
    InvalidAppointmentStatusFilter,
    /// `PATCH /v1/cabinet/quotes/:id` sur un devis déjà signé — remonte le
    /// trigger `enforce_quote_immutable` (migration 0051, SQLSTATE `P0001`)
    /// en `409 quote_locked` (contrat documenté doc12 §16, #4065).
    QuoteLocked,
    /// `POST /v1/quotes/:id/signature` (#4064) : provider de signature
    /// (Yousign) injoignable ou en erreur → `502`, jamais une session
    /// fabriquée côté API.
    UpstreamUnavailable,
    /// `POST /v1/quotes/:id/signature` (#5688) : `YOUSIGN_API_KEY` absente
    /// (provider pas encore provisionné, cf. `deploy.yml`) — distinct d'une
    /// vraie panne provider (`UpstreamUnavailable`) : `503`, pas `502`,
    /// pour ne pas faire passer une lacune de configuration connue pour un
    /// incident Yousign en production.
    SignatureProviderNotConfigured,
    /// `POST /v1/cabinet/cash-register/closing` (#4071) : une clôture existe
    /// déjà pour ce cabinet+jour (`UNIQUE (cabinet_id, closing_date)`,
    /// migration 0165) — pré-vérifiée explicitement plutôt que de laisser
    /// la contrainte remonter en 500.
    CashRegisterAlreadyClosed,
    /// `PATCH /v1/appointments/:id` avec un `starts_at` qui ne correspond à
    /// aucun `availability_slot` ouvert du praticien (ou dans le passé) → 409
    /// (#3558 : reprogrammation vers un créneau inexistant / date passée).
    SlotUnavailable,
    /// `POST /v1/cabinet/consultations/:id/acts` : le `ccam_code` soumis est
    /// à risque au vu d'un flag du dossier médical du patient (#4057, table
    /// de correspondance v1 simple) → 409 bloquant. Le `String` porte le
    /// message d'alerte affiché au praticien (ex. "Anticoagulants —
    /// vérifier le risque hémorragique avant un acte invasif").
    ClinicalRiskWarning(String),
    /// `POST /v1/account/medical-questionnaire` (#4108) : un brouillon existe
    /// déjà pour ce cabinet — le client doit utiliser `PATCH` plutôt que de
    /// créer un doublon (pas de contrainte d'unicité en base, garde applicative).
    MedicalQuestionnaireDraftExists,
    /// `POST /v1/cabinet/practitioners/me/favorite-acts` (#4112) : cet acte
    /// CCAM est déjà dans les favoris de ce praticien (pré-vérifié, la table
    /// a bien `UNIQUE (practitioner_id, ccam_code)` mais l'app évite de
    /// laisser remonter une violation de contrainte brute en 500).
    FavoriteActAlreadyExists,
    /// `POST /v1/cabinet/orthodontics/:id/steps` (#4135) : `step_number`
    /// déjà utilisé pour ce traitement (index unique `(treatment_id,
    /// step_number)`, migration 0189) — même choix que
    /// `FavoriteActAlreadyExists`, pas de violation brute en 500.
    StepNumberTaken,
    /// `POST /v1/cabinet/sterilization-cycles/:id/pouches` (#4139) : `code`
    /// déjà scanné dans ce cabinet (index unique `(cabinet_id, code)`,
    /// migration 0191) — même choix que `StepNumberTaken`.
    PouchCodeAlreadyUsed,
    /// `POST /v1/cabinet/sterilization-cycles` (#4489) : `(autoclave_ref,
    /// cycle_number)` déjà utilisé dans ce cabinet (index unique
    /// `(cabinet_id, autoclave_ref, cycle_number)`, migration 0202) — même
    /// choix que `StepNumberTaken`/`PouchCodeAlreadyUsed` (registre de
    /// traçabilité médico-légale, pas de doublon corrigeable).
    SterilizationCycleNumberAlreadyUsed,
    /// `POST /v1/cabinet/consultations/:id/acts` (#4117) : le code CCAM
    /// soumis figure dans `ccam_act_incompatibility` avec un acte déjà
    /// présent dans la séance — `422` (erreur de saisie côté praticien,
    /// pas un conflit d'état comme `ClinicalRiskWarning` qui, lui, reste
    /// franchissable après revue clinique ; un cumul interdit n'a pas
    /// d'exception). Le `String` porte le motif (`ccam_act_incompatibility.reason`).
    IncompatibleActs(String),
    /// `POST /v1/cabinet/stock-items` (#4144) : `reference` déjà utilisée
    /// dans ce cabinet (index unique `(cabinet_id, reference)`, migration
    /// 0192) — même choix que `StepNumberTaken`/`PouchCodeAlreadyUsed`.
    StockReferenceAlreadyUsed,
    /// `POST /v1/cabinet/ccam-stock-mappings` (#4798) : ce couple
    /// `(cabinet_id, ccam_code, stock_item_id)` a déjà un mapping (index
    /// unique, migration 0192) — même choix que `StockReferenceAlreadyUsed`.
    StockMappingAlreadyExists,
    /// `POST /v1/cabinet/consultations/:id/acts` (#4411) : un acte strictement
    /// identique (même `ccam_code`/`tooth`/`amount_cents`) est déjà présent
    /// sur cette séance — protège contre un double-submit/retry réseau qui
    /// gonflerait le devis facturé au patient. `409`, pas `422` : l'acte en
    /// lui-même est valide, c'est sa répétition qui est refusée.
    DuplicateAct,
    /// `POST /v1/account/dependents` (#4475) : un lien de tutelle actif
    /// existe déjà pour ce couple (guardian, nom+prénom+date de naissance) —
    /// `dependent_account_id` étant toujours neuf, l'index unique
    /// `account_guardianship_active_pair_uidx` (migration 0025) ne peut
    /// jamais se déclencher structurellement ; contrôle applicatif requis.
    DuplicateDependent,
    /// `POST /v1/account/access-requests` (#6119) : une invitation active
    /// (`envoyee` ou `acceptee`, non annulée/révoquée) existe déjà pour ce
    /// couple (requester, email/téléphone) — contrôle applicatif, comme
    /// `DuplicateDependent`.
    DuplicateAccessRequest,
    /// `DELETE /v1/cabinet/consultations/:id/acts/:act_id` (#4481) : l'acte
    /// est référencé par un `stock_movement` ou un `sterilized_pouch` (FK
    /// composite `(consultation_act_id, cabinet_id)` sans `ON DELETE`,
    /// migrations 0190/0192) — pré-vérifié pour éviter de laisser remonter
    /// la violation FK Postgres (23503) en 500.
    ActLinkedToStock,
    /// `POST /v1/account/visit-requests` (#5724) : le patient a déjà une
    /// demande de visite infirmière active (index unique partiel, migration
    /// 0234) — même anti-pattern que `MemberAlreadyExists` (#3828) :
    /// `AppError::Conflict` rend `{"code":"verification_pending"}`, un
    /// contrat trompeur pour un simple doublon de demande.
    VisitRequestAlreadyActive,
    /// `POST /v1/pharmacy/orders/pickup-scan` (#6349) : le token scanné est
    /// valide et `ready`, mais il appartient à une commande DIFFÉRENTE de
    /// celle transmise par le client (`expected_order_id`, écran
    /// `/orders/:id/pickup`) — vérifié AVANT toute écriture, donc aucune
    /// transition n'a lieu. Porte la commande réellement scannée (même
    /// forme que le payload de succès) pour que le front affiche l'encart
    /// de non-correspondance sans re-fetch.
    PickupOrderMismatch(serde_json::Value),
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
                Json(json!({"code": "invalid_status"})),
            )
                .into_response(),
            // #3844 : "hors fenêtre" est un conflit d'état/temps (comme
            // too_early/too_late/invalid_status, tous en 409), pas une erreur
            // de validation de payload. Avant ce fix, la même garde ±60min
            // renvoyait 409 (trop tôt) mais 422 (trop tard) — incohérence
            // contredisant la doc du handler qui promettait 409.
            AppError::OutOfWindow => {
                (StatusCode::CONFLICT, Json(json!({"code": "out_of_window"}))).into_response()
            }
            AppError::TooEarly => {
                (StatusCode::CONFLICT, Json(json!({"code": "too_early"}))).into_response()
            }
            AppError::TooLate => {
                (StatusCode::CONFLICT, Json(json!({"code": "too_late"}))).into_response()
            }
            AppError::LinkExpired => {
                (StatusCode::GONE, Json(json!({"code": "link_expired"}))).into_response()
            }
            AppError::HoldInvalid => {
                (StatusCode::CONFLICT, Json(json!({"code": "hold_invalid"}))).into_response()
            }
            AppError::TooManyRequests(retry_after) => {
                let mut resp = (
                    StatusCode::TOO_MANY_REQUESTS,
                    Json(json!({"code": "too_many_requests"})),
                )
                    .into_response();
                if let Ok(val) = HeaderValue::from_str(&retry_after.to_string()) {
                    resp.headers_mut().insert(RETRY_AFTER, val);
                }
                resp
            }
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
            AppError::InsufficientStock => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "insufficient_stock"})),
            )
                .into_response(),
            AppError::NoActiveMembership => (
                StatusCode::FORBIDDEN,
                Json(json!({"code": "no_membership"})),
            )
                .into_response(),
            AppError::LastAdminCannotBeRemoved => (
                StatusCode::CONFLICT,
                Json(json!({"code": "last_admin_cannot_be_removed"})),
            )
                .into_response(),
            AppError::StartAtNotFuture => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "start_at_not_future"})),
            )
                .into_response(),
            AppError::HasBooking => {
                (StatusCode::CONFLICT, Json(json!({"code": "has_booking"}))).into_response()
            }
            AppError::InvitationInvalid => (
                StatusCode::BAD_REQUEST,
                Json(json!({"code": "invitation_invalid"})),
            )
                .into_response(),
            AppError::AlreadyOrdered => (
                StatusCode::CONFLICT,
                Json(json!({"code": "already_ordered"})),
            )
                .into_response(),
            AppError::IdempotencyKeyConflict => (
                StatusCode::CONFLICT,
                Json(json!({"code": "idempotency_key_conflict"})),
            )
                .into_response(),
            AppError::UnsupportedPageParam => (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "code": "unsupported_pagination_param",
                    "message": "Le paramètre `page` n'est pas supporté sur cet endpoint ; \
                                utilisez `limit` et `offset` pour paginer.",
                })),
            )
                .into_response(),
            AppError::InvalidQuoteStatusFilter => (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "code": "invalid_status_filter",
                    "message": "`status` doit être l'une des valeurs : \
                                draft, sent, signed, refused, expired.",
                })),
            )
                .into_response(),
            AppError::InvalidAppointmentStatusFilter => (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "code": "invalid_status_filter",
                    "message": "`status` doit être l'une des valeurs : \
                                requested, confirmed, checked_in, in_progress, done, cancelled, no_show.",
                })),
            )
                .into_response(),
            AppError::QuoteLocked => {
                (StatusCode::CONFLICT, Json(json!({"code": "quote_locked"}))).into_response()
            }
            AppError::UpstreamUnavailable => (
                StatusCode::BAD_GATEWAY,
                Json(json!({"code": "upstream_unavailable"})),
            )
                .into_response(),
            AppError::SignatureProviderNotConfigured => (
                StatusCode::SERVICE_UNAVAILABLE,
                Json(json!({"code": "signature_provider_not_configured"})),
            )
                .into_response(),
            AppError::CashRegisterAlreadyClosed => (
                StatusCode::CONFLICT,
                Json(json!({"code": "cash_register_already_closed"})),
            )
                .into_response(),
            AppError::SlotUnavailable => (
                StatusCode::CONFLICT,
                Json(json!({"code": "slot_unavailable"})),
            )
                .into_response(),
            AppError::ClinicalRiskWarning(message) => (
                StatusCode::CONFLICT,
                Json(json!({"code": "clinical_risk_warning", "message": message})),
            )
                .into_response(),
            AppError::MedicalQuestionnaireDraftExists => (
                StatusCode::CONFLICT,
                Json(json!({"code": "medical_questionnaire_draft_exists"})),
            )
                .into_response(),
            AppError::FavoriteActAlreadyExists => (
                StatusCode::CONFLICT,
                Json(json!({"code": "favorite_act_already_exists"})),
            )
                .into_response(),
            AppError::StepNumberTaken => (
                StatusCode::CONFLICT,
                Json(json!({"code": "step_number_taken"})),
            )
                .into_response(),
            AppError::PouchCodeAlreadyUsed => (
                StatusCode::CONFLICT,
                Json(json!({"code": "pouch_code_already_used"})),
            )
                .into_response(),
            AppError::SterilizationCycleNumberAlreadyUsed => (
                StatusCode::CONFLICT,
                Json(json!({"code": "sterilization_cycle_number_already_used"})),
            )
                .into_response(),
            AppError::IncompatibleActs(reason) => (
                StatusCode::UNPROCESSABLE_ENTITY,
                Json(json!({"code": "incompatible_acts", "reason": reason})),
            )
                .into_response(),
            AppError::StockReferenceAlreadyUsed => (
                StatusCode::CONFLICT,
                Json(json!({"code": "stock_reference_already_used"})),
            )
                .into_response(),
            AppError::StockMappingAlreadyExists => (
                StatusCode::CONFLICT,
                Json(json!({"code": "stock_mapping_already_exists"})),
            )
                .into_response(),
            AppError::DuplicateAct => (
                StatusCode::CONFLICT,
                Json(json!({"code": "duplicate_act"})),
            )
                .into_response(),
            AppError::DuplicateDependent => (
                StatusCode::CONFLICT,
                Json(json!({"code": "duplicate_dependent"})),
            )
                .into_response(),
            AppError::DuplicateAccessRequest => (
                StatusCode::CONFLICT,
                Json(json!({"code": "duplicate_access_request"})),
            )
                .into_response(),
            AppError::ActLinkedToStock => (
                StatusCode::CONFLICT,
                Json(json!({"code": "act_linked_to_stock"})),
            )
                .into_response(),
            AppError::VisitRequestAlreadyActive => (
                StatusCode::CONFLICT,
                Json(json!({"code": "visit_request_already_active"})),
            )
                .into_response(),
            AppError::PickupOrderMismatch(order) => (
                StatusCode::CONFLICT,
                Json(json!({"code": "pickup_order_mismatch", "order": order})),
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
    /// Présents uniquement dans les tokens `kind:"pharma"` (émis par
    /// `select-pharmacy-context`) — #3853.
    pub(crate) pharmacy_id: Option<Uuid>,
    pub(crate) role: Option<String>,
}

/// Appartenance à un cabinet.
#[derive(Serialize)]
pub struct CabinetMembership {
    cabinet_id: Uuid,
    role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    secretariat_id: Option<Uuid>,
    cabinet_name: String,
    /// Id `practitioner` (distinct de `user_id`, cf. #6251) pour ce cabinet —
    /// `None` si l'utilisateur n'a pas d'entité praticien dans ce cabinet
    /// (secrétaire, admin non-praticien).
    #[serde(skip_serializing_if = "Option::is_none")]
    practitioner_id: Option<Uuid>,
}

/// Appartenance à une pharmacie.
#[derive(Serialize)]
pub struct PharmacyMembership {
    pharmacy_id: Uuid,
    role: String,
    pharmacy_name: String,
}

/// Réponse de `GET /v1/me`.
#[derive(Serialize)]
pub struct MeResponse {
    user_id: Uuid,
    email: String,
    kind: String,
    account_id: Option<Uuid>,
    /// Nom affichable de l'utilisateur (#6170, même cause que #6165) —
    /// `"{first_name} {last_name}"` (`app_user`), `None` si les deux sont
    /// vides (compte pro seedé sans identité, cf. `db/seed/seed.sql`).
    display_name: Option<String>,
    memberships: Vec<CabinetMembership>,
    pharmacy_memberships: Vec<PharmacyMembership>,
}

/// `GET /v1/me` — retourne le profil du porteur du token (patient, pro ou pharma).
///
/// Pour les tokens pro portant un `cabinet_id` (émis par `POST /v1/pro/register`),
/// interroge `cabinet_membership` via RLS (SET LOCAL). Pour les tokens pro sans
/// `cabinet_id` (émis par `POST /v1/auth/login`), `memberships` est vide.
/// Pour un token `kind:"pharma"` déjà scopé (émis par `select-pharmacy-context`),
/// `pharmacy_memberships` est dérivé directement de ses propres claims (#3853) —
/// sans cette dérivation, un restore de session sur un token pharma persisté
/// obtenait une liste vide et déclenchait une déconnexion silencieuse.
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
    let row = sqlx::query("SELECT email, first_name, last_name FROM app_user WHERE id = $1")
        .bind(claims.sub)
        .fetch_one(&mut *etx)
        .await
        .map_err(|_| AppError::Internal)?;
    etx.commit().await.map_err(|_| AppError::Internal)?;

    let email: String = row.try_get("email").map_err(|_| AppError::Internal)?;
    let first_name: Option<String> = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: Option<String> = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    // #6170 (même cause que #6165) : le shell pro n'affiche jamais l'identité
    // réelle faute de display_name exposé par /me — first_name/last_name
    // existent déjà sur app_user (migration 0021) mais n'étaient jamais lus ici.
    let display_name = [first_name, last_name]
        .into_iter()
        .flatten()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect::<Vec<_>>()
        .join(" ");
    let display_name = if display_name.is_empty() {
        None
    } else {
        Some(display_name)
    };

    // Pour les tokens pro (login ou register), retourne tous les memberships actifs
    // via user_all_memberships() (SECURITY DEFINER — contourne la RLS cabinet-scoped).
    let memberships = if claims.kind == "pro" {
        let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(claims.sub.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
        let rows = sqlx::query(
            "SELECT cabinet_id, role, secretariat_id, cabinet_name \
             FROM user_all_memberships($1)",
        )
        .bind(claims.sub)
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
        tx.commit().await.map_err(|_| AppError::Internal)?;

        // Mapping cabinet_id -> practitioner_id (#6251) : `practitioner` n'a pas
        // de RLS (table jointe librement depuis /v1/cabinet/agenda), une seule
        // requête couvre tous les cabinets de l'utilisateur. `session.userId`
        // (= claims.sub, un `app_user.id`) n'est PAS un `practitioner_id` — ce
        // sont deux entités distinctes (`practitioner.user_id` référence l'une
        // vers l'autre) ; sans cette résolution, le front n'a aucun moyen de
        // savoir quel practitioner_id correspond à l'utilisateur connecté.
        let practitioner_ids_by_cabinet: std::collections::HashMap<Uuid, Uuid> =
            sqlx::query("SELECT cabinet_id, id FROM practitioner WHERE user_id = $1")
                .bind(claims.sub)
                .fetch_all(&state.db)
                .await
                .map_err(|_| AppError::Internal)?
                .into_iter()
                .map(|r| {
                    let cabinet_id: Uuid =
                        r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                    let practitioner_id: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
                    Ok((cabinet_id, practitioner_id))
                })
                .collect::<Result<_, AppError>>()?;

        rows.into_iter()
            .map(|r| {
                let cid: Uuid = r.try_get("cabinet_id").map_err(|_| AppError::Internal)?;
                let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
                let secretariat_id: Option<Uuid> = r
                    .try_get("secretariat_id")
                    .map_err(|_| AppError::Internal)?;
                let cabinet_name: String =
                    r.try_get("cabinet_name").map_err(|_| AppError::Internal)?;
                let practitioner_id = practitioner_ids_by_cabinet.get(&cid).copied();
                Ok(CabinetMembership {
                    cabinet_id: cid,
                    role,
                    secretariat_id,
                    cabinet_name,
                    practitioner_id,
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?
    } else {
        vec![]
    };

    // Memberships pharmacie (tenant dédié, cf. migration 0121) : mêmes tokens de
    // login `kind == "pro"`, résolus via user_pharmacy_memberships() (SECURITY
    // DEFINER — contourne la RLS pharmacy-scoped). Permet au front pharmacie de
    // savoir quel contexte proposer avant POST /v1/auth/select-pharmacy-context.
    //
    // `kind == "pharma"` (#3853) : le token DÉJÀ scopé porte pharmacy_id/role
    // dans ses propres claims — pas besoin de requête, on les redérive tels
    // quels. Avant ce fix, `pharmacy_memberships` restait vide pour ce kind :
    // au restore de session (reload de page), le front persiste le DERNIER
    // token (celui de select-pharmacy-context, kind=pharma, jamais kind=pro),
    // relit `/me`, obtient `pharmacy_memberships:[]`, et déconnecte
    // silencieusement le pharmacien en effaçant son token pourtant valide.
    let pharmacy_memberships = if claims.kind == "pro" {
        let rows = sqlx::query(
            "SELECT pharmacy_id, role, pharmacy_name FROM user_pharmacy_memberships($1)",
        )
        .bind(claims.sub)
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;
        rows.into_iter()
            .map(|r| {
                let pharmacy_id: Uuid = r.try_get("pharmacy_id").map_err(|_| AppError::Internal)?;
                let role: String = r.try_get("role").map_err(|_| AppError::Internal)?;
                let pharmacy_name: String =
                    r.try_get("pharmacy_name").map_err(|_| AppError::Internal)?;
                Ok(PharmacyMembership {
                    pharmacy_id,
                    role,
                    pharmacy_name,
                })
            })
            .collect::<Result<Vec<_>, AppError>>()?
    } else if claims.kind == "pharma" {
        match (claims.pharmacy_id, claims.role.clone()) {
            (Some(pharmacy_id), Some(role)) => {
                // Token déjà scopé (#3853) : pharmacy_id/role viennent des
                // claims, mais leur nom n'y est pas porté — on le redérive
                // via la même fonction SECURITY DEFINER (contourne la RLS
                // pharmacy-scoped, cf. select_pharmacy_context.rs).
                let row = sqlx::query(
                    "SELECT pharmacy_name FROM user_pharmacy_memberships($1) \
                     WHERE pharmacy_id = $2",
                )
                .bind(claims.sub)
                .bind(pharmacy_id)
                .fetch_optional(&state.db)
                .await
                .map_err(|_| AppError::Internal)?;
                let pharmacy_name = row
                    .and_then(|r| r.try_get::<String, _>("pharmacy_name").ok())
                    .unwrap_or_default();
                vec![PharmacyMembership {
                    pharmacy_id,
                    role,
                    pharmacy_name,
                }]
            }
            _ => vec![],
        }
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
        display_name,
        memberships,
        pharmacy_memberships,
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
///
/// Anti-énumération (#3748) : email déjà pris → `201` générique quand même (aucun
/// compte créé, JWT décoratif sur des IDs jetables), jamais `409 email_taken`.
pub async fn pro_register(
    State(state): State<AppState>,
    Json(body): Json<ProRegisterBody>,
) -> Result<(StatusCode, Json<ProRegisterResponse>), AppError> {
    if body.password.len() < 8 || !body.password.chars().any(|c| c.is_ascii_digit()) {
        return Err(AppError::PasswordPolicy);
    }

    if body.cabinet.raison_sociale.trim().is_empty()
        || body.cabinet.specialite.trim().is_empty()
        || body.practitioner.first_name.trim().is_empty()
        || body.practitioner.last_name.trim().is_empty()
    {
        return Err(AppError::ValidationError);
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
    let insert_result = sqlx::query(
        "INSERT INTO app_user (id, email, password_hash, kind) VALUES ($1, $2, $3, 'pro')",
    )
    .bind(user_id)
    .bind(&body.email)
    .bind(&password_hash)
    .execute(&mut *tx)
    .await;
    if let Err(e) = insert_result {
        if is_unique_violation(&e) {
            // Anti-énumération (#3748) : un 409 email_taken vs 201 est un oracle
            // fiable d'existence de compte sur un endpoint anonyme sans rate-limit
            // ni CAPTCHA. `tx` n'est jamais commit (drop = rollback implicite) —
            // aucune écriture, aucun compte réel ni token n'accède au compte
            // d'autrui. Réponse 201 structurellement indiscernable d'un succès :
            // mêmes types de champs, un vrai JWT signé (même format/longueur),
            // mais portant des IDs jetables jamais persistés en base — inutilisable
            // pour accéder à quoi que ce soit.
            tracing::warn!(
                "pro_register: tentative sur un email déjà pris (anti-énumération, aucun compte créé)"
            );
            let decoy_user_id = Uuid::new_v4();
            let decoy_cabinet_id = Uuid::new_v4();
            let exp = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs()
                + 900;
            let decoy_claims = ProRegisterClaims {
                sub: decoy_user_id,
                kind: "pro".to_string(),
                cabinet_id: decoy_cabinet_id,
                role: "admin".to_string(),
                secretariat_id: None,
                exp,
            };
            let access_token = encode(
                &Header::default(),
                &decoy_claims,
                &EncodingKey::from_secret(state.jwt_secret.as_bytes()),
            )
            .map_err(|_| AppError::Internal)?;
            return Ok((
                StatusCode::CREATED,
                Json(ProRegisterResponse {
                    account_id: decoy_user_id,
                    cabinet_id: decoy_cabinet_id,
                    provider_id: Uuid::new_v4(),
                    access_token,
                }),
            ));
        }
        return Err(AppError::Internal);
    }

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

    // Ligne cabinet-interne (0002_cabinet_identity.sql), sans laquelle le cabinet
    // n'a aucun praticien exploitable : `create_cabinet_slot` (scheduling.rs) et
    // `get_cabinet_agenda` ne lisent que `practitioner`, jamais `provider`.
    let practitioner_row = sqlx::query(
        "INSERT INTO practitioner (cabinet_id, user_id, rpps, specialite) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(&body.practitioner.rpps)
    .bind(&body.cabinet.specialite)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = practitioner_row
        .try_get(0)
        .map_err(|_| AppError::Internal)?;

    // Profil marketplace public, lié au praticien cabinet via `practitioner_id`
    // (colonne nullable, 0009_marketplace.sql) — c'est ce lien que
    // `create_cabinet_slot` utilise pour retrouver le provider associé.
    let provider_row = sqlx::query(
        "INSERT INTO provider (cabinet_id, user_id, practitioner_id, display_name, rpps, adeli) \
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
    )
    .bind(cabinet_id)
    .bind(user_id)
    .bind(practitioner_id)
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
    if let Some(name) = &body.name {
        crate::text_validation::reject_nul_byte(name)?;
        if name.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(siret) = &body.siret {
        crate::text_validation::reject_nul_byte(siret)?;
    }
    if let Some(addr) = &body.address {
        crate::text_validation::reject_nul_byte(addr)?;
    }
    if let Some(phone) = &body.phone {
        crate::text_validation::reject_nul_byte(phone)?;
    }
    if let Some(s) = &body.settings {
        crate::text_validation::reject_nul_byte_in_json(s)?;
    }

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
///
/// RBAC : le profil provider interrogé est CELUI DE L'APPELANT (`user_id = sub`).
/// Seul un praticien possède un profil provider ; l'endpoint est donc réservé aux
/// rôles `practitioner`/`admin` (`ProPractitionerClaims`) et non à `admin` seul —
/// sinon un praticien ne peut pas consulter son propre statut de vérif (#3412).
pub async fn get_pro_verification(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<ProVerificationStatusResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Pas de profil provider pour l'appelant (ex. admin non-praticien) → 404 propre,
    // jamais un 500 (#3412).
    let provider_row =
        sqlx::query("SELECT id FROM provider WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
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

        // Première passe : extrait `kind` pour renvoyer 403 (pas 401)
        // si le token est valide mais n'appartient pas à un pro (ex. token
        // patient) — #3806, décoder directement ProAdminClaims (cabinet_id/role
        // obligatoires, absents d'un token patient) faisait échouer serde
        // avant même le test kind, retombant sur 401 Unauthorized.
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pro obligatoires (cabinet_id, role).
        let claims = decode::<ProAdminClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

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
    pub(crate) cabinet_id: Uuid,
    pub(crate) role: String,
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

        // Première passe : extrait `kind` pour renvoyer 403 (pas 401) — #3806,
        // même défaut que ProAdminClaims (décoder directement échouait la
        // désérialisation serde pour un token patient, avant le test kind).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pro" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pro obligatoires (cabinet_id, role).
        let claims = decode::<ProAdminOrManagerClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

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
    pub(crate) role: String,
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

/// Claims JWT pharmacie, tout rôle actif (`pharmacist`, `preparator`, `admin`).
///
/// Émis par `POST /v1/auth/select-pharmacy-context` (`kind == "pharma"`).
/// Renvoie `401` si absent/invalide, `403` si `kind != "pharma"` — un token
/// pro ou patient ne peut jamais ouvrir l'espace pharmacie (cloisonnement
/// structurel, docs/07 §4).
#[derive(Debug, Deserialize)]
pub(crate) struct PharmaMemberClaims {
    pub(crate) sub: Uuid,
    pub(crate) pharmacy_id: Uuid,
    #[allow(dead_code)] // consommé au lot B3 (reject réservé pharmacist/admin)
    pub(crate) role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for PharmaMemberClaims {
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
        // si le token est valide mais n'est pas un token pharmacie (ex. pro/patient).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "pharma" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs pharmacie obligatoires.
        let claims = decode::<PharmaMemberClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        Ok(claims)
    }
}

/// Claims JWT pharmacie avec rôle décisionnaire (`pharmacist` ou `admin`) —
/// rejette `preparator` (403). Requis pour refuser une commande ou envoyer
/// un devis.
#[derive(Debug, Deserialize)]
pub(crate) struct PharmaPharmacistClaims {
    pub(crate) sub: Uuid,
    pub(crate) pharmacy_id: Uuid,
    role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for PharmaPharmacistClaims {
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

        if basic.kind != "pharma" {
            return Err(AppError::Forbidden);
        }

        let claims = decode::<PharmaPharmacistClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if claims.role != "pharmacist" && claims.role != "admin" {
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

/// Claims JWT émis par `POST /v1/auth/select-pharmacy-context` —
/// porte `pharmacy_id` + `role` avec `kind = "pharma"`.
///
/// GUC et audience distincts du tenant cabinet : un token pharma est rejeté
/// (403) par tous les extracteurs `Pro*Claims`, et réciproquement.
#[derive(Serialize, Deserialize)]
pub(crate) struct PharmaContextClaims {
    pub(crate) sub: Uuid,
    pub(crate) kind: String,
    pub(crate) pharmacy_id: Uuid,
    pub(crate) role: String,
    pub(crate) exp: u64,
}

/// Claims JWT émis par `POST /v1/auth/select-nurse-context` — porte `nurse_id` +
/// `role` avec `kind = "nurse"`. GUC et audience distincts des tenants
/// cabinet/pharmacie : un token nurse est rejeté (403) par les extracteurs
/// `Pro*Claims`/`Pharma*Claims`, et réciproquement. Clone de `PharmaContextClaims`.
#[derive(Serialize, Deserialize)]
pub(crate) struct NurseContextClaims {
    pub(crate) sub: Uuid,
    pub(crate) kind: String,
    pub(crate) nurse_id: Uuid,
    pub(crate) role: String,
    pub(crate) exp: u64,
}

/// Extracteur des endpoints `/v1/nurse/*` : exige un token `kind:"nurse"` (issu de
/// select-nurse-context). Clone de `PharmaMemberClaims` (double passe : 403 si le
/// token est valide mais pas un token infirmier).
#[derive(Debug, Deserialize)]
pub(crate) struct NurseMemberClaims {
    #[allow(dead_code)] // présent dans le JWT ; les handlers scopent via nurse_id
    pub(crate) sub: Uuid,
    pub(crate) nurse_id: Uuid,
    #[allow(dead_code)] // consommé par les endpoints réservés au rôle admin
    pub(crate) role: String,
}

#[async_trait]
impl FromRequestParts<AppState> for NurseMemberClaims {
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

        // Première passe : `kind` seul → 403 (pas 401) si le token est valide mais
        // n'est pas un token infirmier (ex. pro/pharma/patient).
        let basic = decode::<KindClaims>(token, &key, &validation)
            .map(|d| d.claims)
            .map_err(|_| AppError::Unauthorized)?;

        if basic.kind != "nurse" {
            return Err(AppError::Forbidden);
        }

        // Deuxième passe : décode les champs infirmier obligatoires.
        let claims = decode::<NurseMemberClaims>(token, &key, &validation)
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
    cabinet_id: Uuid,
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

        let user_row =
            sqlx::query("SELECT email, first_name, last_name FROM app_user WHERE id = $1")
                .bind(user_id)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?;
        let (email, first_name, last_name) = match user_row {
            Some(r) => (
                r.try_get::<String, _>("email").unwrap_or_default(),
                r.try_get::<Option<String>, _>("first_name").unwrap_or(None),
                r.try_get::<Option<String>, _>("last_name").unwrap_or(None),
            ),
            None => (String::new(), None, None),
        };

        members.push(CabinetMemberItem {
            user_id,
            cabinet_id: claims.cabinet_id,
            email,
            first_name,
            last_name,
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

/// Validation de format email minimale (syntaxique, pas de vérification DNS/MX) :
/// exactement un `@`, partie locale et domaine non vides, domaine contenant un
/// point, aucun espace. Suffisant pour rejeter les fautes de frappe grossières
/// (#3879 : "not-an-email" créait un compte pro orphelin + gaspillait le slot
/// UNIQUE(email)) sans dépendance externe — pas une validation RFC 5322 complète.
fn is_valid_email_format(email: &str) -> bool {
    let email = email.trim();
    if email.is_empty() || email.chars().any(char::is_whitespace) {
        return false;
    }
    let Some((local, domain)) = email.split_once('@') else {
        return false;
    };
    if local.is_empty() || domain.is_empty() || domain.contains('@') {
        return false;
    }
    domain.contains('.') && !domain.starts_with('.') && !domain.ends_with('.')
}

/// `POST /v1/cabinet/members` — crée un compte collaborateur et l'invite par email.
///
/// Si l'email est inconnu : crée `app_user` (password_hash NULL) + token invite 72 h
/// stocké dans `password_reset_token`. Si l'email correspond à un membre RETIRÉ de ce
/// cabinet (adhésion inactive) : réactive l'adhésion existante (`200`) plutôt que de
/// heurter l'unicité de l'email (#3878). Si l'email est déjà membre ACTIF du même
/// cabinet → `409`. Si `rpps` est fourni et `role=practitioner` → crée une entrée
/// `provider`. `email` syntaxiquement invalide → `422` (#3879). Rôle `admin` requis.
pub async fn post_cabinet_members(
    State(state): State<AppState>,
    claims: ProAdminClaims,
    Json(body): Json<PostCabinetMemberBody>,
) -> Result<(StatusCode, Json<CabinetMemberItem>), AppError> {
    // Rôles valides pour `cabinet_membership` (cf. `patch_cabinet_member`) :
    // `manager` est un rôle de secrétariat, pas de cabinet ; le rôle
    // praticien s'appelle `practitioner` (pas `doctor`).
    if !["practitioner", "secretary", "admin"].contains(&body.role.as_str()) {
        return Err(AppError::ValidationError);
    }
    if !is_valid_email_format(&body.email) {
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

    // Ré-invitation d'un membre retiré (#3878) : app_user.email est unique
    // globalement ; sans ce contrôle, un membre soft-deleted (active=false)
    // heurtait à vie 23505 sur l'INSERT app_user → 409 permanent, aucun chemin
    // de réactivation. reactivate_cabinet_member (SECURITY DEFINER, migration
    // 0148) contourne la RLS pour retrouver le compte par email et réactiver
    // son adhésion à CE cabinet si elle est inactive.
    let reactivation = sqlx::query(
        "SELECT matched_user_id, already_active FROM reactivate_cabinet_member($1, $2, $3)",
    )
    .bind(claims.cabinet_id)
    .bind(&body.email)
    .bind(&body.role)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if let Some(row) = reactivation {
        let matched_user_id: Uuid = row
            .try_get("matched_user_id")
            .map_err(|_| AppError::Internal)?;
        let already_active: bool = row
            .try_get("already_active")
            .map_err(|_| AppError::Internal)?;

        if already_active {
            return Err(AppError::MemberAlreadyExists);
        }

        // Relit le profil via le même contournement RLS que get_cabinet_members
        // (user_self_select exige current_user_id = id de la ligne lue).
        sqlx::query("SELECT set_config('app.current_user_id', $1, true)")
            .bind(matched_user_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        let member_row = sqlx::query(
            "SELECT au.email, au.first_name, au.last_name, cm.created_at AS joined_at \
             FROM cabinet_membership cm JOIN app_user au ON au.id = cm.user_id \
             WHERE cm.cabinet_id = $1 AND cm.user_id = $2",
        )
        .bind(claims.cabinet_id)
        .bind(matched_user_id)
        .fetch_one(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let email: String = member_row
            .try_get("email")
            .map_err(|_| AppError::Internal)?;
        let first_name: Option<String> = member_row
            .try_get("first_name")
            .map_err(|_| AppError::Internal)?;
        let last_name: Option<String> = member_row
            .try_get("last_name")
            .map_err(|_| AppError::Internal)?;
        let joined_at: chrono::DateTime<chrono::Utc> = member_row
            .try_get("joined_at")
            .map_err(|_| AppError::Internal)?;

        tx.commit().await.map_err(|_| AppError::Internal)?;

        tracing::info!(
            cabinet_id = %claims.cabinet_id,
            user_id = %matched_user_id,
            role = %body.role,
            "cabinet member reactivated"
        );

        return Ok((
            StatusCode::OK,
            Json(CabinetMemberItem {
                user_id: matched_user_id,
                cabinet_id: claims.cabinet_id,
                email,
                first_name,
                last_name,
                role: body.role,
                active: true,
                joined_at: joined_at.to_rfc3339(),
            }),
        ));
    }

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
            cabinet_id: claims.cabinet_id,
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

    if body
        .first_name
        .as_deref()
        .is_some_and(|s| s.trim().is_empty())
        || body
            .last_name
            .as_deref()
            .is_some_and(|s| s.trim().is_empty())
    {
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

/// Valide le format d'un NSS fourni explicitement au PATCH (#3847) :
/// 13-15 chiffres (espaces tolérés, comme `mask_nss`), rejette toute autre
/// forme — chaîne vide, texte non numérique, longueur invalide. Avant ce
/// fix, `body.nss` n'était jamais validé (contrairement à
/// `regime_obligatoire` juste à côté) : une valeur invalide était acceptée
/// (200), écrasait le NSS existant via `COALESCE`, puis devenait illisible
/// via `mask_nss` (< 13 chiffres → `None`) — perte silencieuse d'un PII critique.
fn validate_nss(value: &Option<String>) -> Result<(), AppError> {
    if let Some(v) = value {
        let digits: String = v.chars().filter(|c| c.is_ascii_digit()).collect();
        let non_digit_non_space = v.chars().any(|c| !c.is_ascii_digit() && !c.is_whitespace());
        if non_digit_non_space || !(13..=15).contains(&digits.len()) {
            return Err(AppError::ValidationError);
        }
    }
    Ok(())
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

/// Rejette une chaîne vide/whitespace-only fournie explicitement pour un champ
/// couverture requis (amc/numero_adherent) : `Some("")` passe `COALESCE($n, ...)`
/// (n'est pas NULL) et écrase silencieusement la valeur existante en base avec
/// une chaîne vide (#3797, même gap non couvert par la validation regime_obligatoire
/// juste à côté).
fn validate_coverage_field_non_empty(value: &Option<String>) -> Result<(), AppError> {
    if let Some(v) = value {
        if v.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
    }
    Ok(())
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
/// Exception : `mutuelle` fournie sans `plateforme` remet la plateforme à
/// NULL (#3817) — `mutuelle` porte une identité complète, la plateforme
/// tiers-payant de l'ancien organisme ne doit jamais lui survivre.
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

    validate_nss(&body.nss)?;

    // dev/test : bytes UTF-8 du NSS plaintext (KMS AES-256-GCM à partir de NUB-T3).
    let nss_encrypted: Option<Vec<u8>> = body.nss.as_deref().map(|s| s.as_bytes().to_vec());

    // #3817 : `mutuelle` porte une identité COMPLÈTE (amc+numero_adherent
    // obligatoires sur le sous-objet) — un PATCH qui la fournit réaffirme
    // TOUJOURS l'organisme, y compris sa plateforme tiers-payant (absente =
    // explicitement remise à NULL, jamais héritée de l'ancien organisme).
    // Distinct d'un PATCH qui omet `mutuelle` entièrement (ne touche à rien).
    let mutuelle_provided = body.mutuelle.is_some();
    let (mutuelle_amc, mutuelle_numero, mutuelle_plateforme) = match body.mutuelle {
        Some(m) => {
            if m.amc.trim().is_empty() || m.numero_adherent.trim().is_empty() {
                return Err(AppError::ValidationError);
            }
            (Some(m.amc), Some(m.numero_adherent), m.plateforme)
        }
        None => (None, None, None),
    };

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Régime avant modification (#4095) — capturé avant l'upsert pour
    // journaliser l'ancien/nouveau régime dans audit_log. `None` si aucune
    // ligne patient_coverage n'existait encore (première déclaration).
    let old_regime_obligatoire: Option<String> = sqlx::query(
        "SELECT regime_obligatoire FROM patient_coverage WHERE patient_account_id = $1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .map(|r| r.try_get("regime_obligatoire"))
    .transpose()
    .map_err(|_: sqlx::Error| AppError::Internal)?
    .flatten();

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
           plateforme         = CASE WHEN $8 THEN $6 ELSE patient_coverage.plateforme END, \
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
    .bind(mutuelle_provided)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    // Audit log : entité plateforme → nil UUID comme sentinel cabinet_id.
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(Uuid::nil().to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Nouveau régime (#4095) : relu depuis `row` (RETURNING) plutôt que
    // `body.regime_obligatoire`, qui est `None` si le champ était absent du
    // PATCH (champ non modifié, mais le régime existant reste pertinent à
    // journaliser comme "nouveau" — c'est la valeur effective post-upsert).
    let new_regime_obligatoire: Option<String> = row
        .try_get("regime_obligatoire")
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, 'patient', 'update_coverage', 'patient_coverage', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(json!({
        "old_regime_obligatoire": old_regime_obligatoire,
        "new_regime_obligatoire": new_regime_obligatoire,
    }))
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
    // Fichier vide : même garde que POST /documents (#3552), angle mort non répliqué ici (#3731).
    if file_bytes.is_empty() {
        return Err(AppError::ValidationError);
    }
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

/// Réponse de `GET`/`PUT /v1/account/referring-doctor`.
#[derive(Serialize)]
pub struct ReferringDoctorResponse {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub provider_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free_name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free_phone: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub free_address: Option<String>,
}

const NO_REFERRING_DOCTOR: ReferringDoctorResponse = ReferringDoctorResponse {
    provider_id: None,
    free_name: None,
    free_phone: None,
    free_address: None,
};

/// `GET /v1/account/referring-doctor` — retourne le médecin traitant déclaré par le patient.
///
/// Aucune déclaration existante → `200` avec tous les champs `null` (comme `patient_coverage`).
pub async fn get_account_referring_doctor(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<ReferringDoctorResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT provider_id, free_name, free_phone, free_address \
         FROM patient_referring_doctor \
         WHERE patient_account_id = $1",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let Some(row) = row else {
        return Ok(Json(NO_REFERRING_DOCTOR));
    };

    Ok(Json(ReferringDoctorResponse {
        provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
        free_name: row.try_get("free_name").map_err(|_| AppError::Internal)?,
        free_phone: row.try_get("free_phone").map_err(|_| AppError::Internal)?,
        free_address: row
            .try_get("free_address")
            .map_err(|_| AppError::Internal)?,
    }))
}

/// Corps de la requête `PUT /v1/account/referring-doctor`.
#[derive(Deserialize)]
pub struct PutReferringDoctorBody {
    /// Référence vers un praticien listé dans l'annuaire Nubia.
    provider_id: Option<Uuid>,
    /// Saisie libre — médecin hors base Nubia. `free_name` obligatoire dans ce cas.
    free_name: Option<String>,
    free_phone: Option<String>,
    free_address: Option<String>,
}

/// `PUT /v1/account/referring-doctor` — déclare (ou remplace) le médecin traitant du patient.
///
/// Deux cas exclusifs (issue #3451) :
/// - `provider_id` seul : référence un praticien de l'annuaire Nubia (`provider`,
///   visible via la policy `provider_public_read` → `is_listed = true`, sinon `404`).
/// - `free_name` (+ `free_phone`/`free_address` optionnels) : médecin hors base,
///   aucune fiche praticien n'est créée.
///
/// Ni l'un ni l'autre, ou les deux à la fois → `422`.
/// Remplace intégralement la déclaration existante (upsert `ON CONFLICT (patient_account_id)`).
pub async fn put_account_referring_doctor(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PutReferringDoctorBody>,
) -> Result<Json<ReferringDoctorResponse>, AppError> {
    let free_name = body.free_name.filter(|s| !s.trim().is_empty());

    if body.provider_id.is_some() == free_name.is_some() {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // `provider` reste soumis à sa propre RLS (provider_public_read : is_listed = true) :
    // un provider inconnu ou non listé est invisible ici → 404.
    if let Some(provider_id) = body.provider_id {
        sqlx::query("SELECT id FROM provider WHERE id = $1")
            .bind(provider_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?
            .ok_or(AppError::NotFound)?;
    }

    // Exclusivité provider_id / free_* : la garde ci-dessus ne compare que
    // provider_id.is_some() == free_name.is_some(), elle ignore free_phone/
    // free_address — liés inconditionnellement plus bas, ce qui stockait les
    // deux ensemble en violation du contrat (#3798). Force-les à NULL côté
    // provider pour que le contrat reste vrai en base, pas seulement en entrée.
    let (free_phone, free_address) = if body.provider_id.is_some() {
        (None, None)
    } else {
        (body.free_phone, body.free_address)
    };

    let row = sqlx::query(
        "INSERT INTO patient_referring_doctor \
           (patient_account_id, provider_id, free_name, free_phone, free_address) \
         VALUES ($1, $2, $3, $4, $5) \
         ON CONFLICT (patient_account_id) DO UPDATE SET \
           provider_id  = $2, \
           free_name    = $3, \
           free_phone   = $4, \
           free_address = $5, \
           updated_at   = now() \
         RETURNING provider_id, free_name, free_phone, free_address",
    )
    .bind(claims.account_id)
    .bind(body.provider_id)
    .bind(&free_name)
    .bind(&free_phone)
    .bind(&free_address)
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
         VALUES ($1, $2, 'patient', 'update_referring_doctor', 'patient_referring_doctor', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(json!({"provider_id": body.provider_id, "free_name": free_name}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        user_id = %claims.sub,
        provider_id = ?body.provider_id,
        "patient referring doctor updated"
    );

    Ok(Json(ReferringDoctorResponse {
        provider_id: row.try_get("provider_id").map_err(|_| AppError::Internal)?,
        free_name: row.try_get("free_name").map_err(|_| AppError::Internal)?,
        free_phone: row.try_get("free_phone").map_err(|_| AppError::Internal)?,
        free_address: row
            .try_get("free_address")
            .map_err(|_| AppError::Internal)?,
    }))
}

/// `DELETE /v1/account/referring-doctor` — retire le médecin traitant déclaré par le patient.
///
/// Idempotent : `204` que la déclaration existe ou non (jamais de `404`).
pub async fn delete_account_referring_doctor(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<StatusCode, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query("DELETE FROM patient_referring_doctor WHERE patient_account_id = $1")
        .bind(claims.account_id)
        .execute(&mut *tx)
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
         VALUES ($1, $2, 'patient', 'delete_referring_doctor', 'patient_referring_doctor', $3, $4)",
    )
    .bind(Uuid::nil())
    .bind(claims.sub)
    .bind(claims.account_id)
    .bind(json!({}))
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        account_id = %claims.account_id,
        user_id = %claims.sub,
        "patient referring doctor deleted"
    );

    Ok(StatusCode::NO_CONTENT)
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

/// Référentiel canonique des `purpose` de consentement RGPD gérables (octroi
/// ET retrait) — partagé entre `put_account_consent` et `get_account_consents`
/// (#3819 : GET exposait des purposes historiques/hors-référentiel comme
/// `data_processing`, non gérables via PUT — cul-de-sac RGPD, un consentement
/// affiché `granted=true` doit toujours rester révocable, art. 7-3).
const CONSENT_PURPOSES: [&str; 5] = [
    "soins",
    "ia_scribe",
    "marketing",
    "partage_confrere",
    "partage_pharmacie",
];

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
    if !CONSENT_PURPOSES.contains(&purpose.as_str()) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Les consentements RGPD du portail patient sont scopés `patient_account_id` ;
    // `app_user_id` reste NULL (migration 0050 l'a rendu nullable exprès). L'ancien
    // code liait aussi `app_user_id = claims.sub`, ce qui entrait en collision avec
    // la contrainte UNIQUE (app_user_id, purpose) 0027 dès qu'une ligne CGU plateforme
    // existait déjà pour ce user (seed « soins ») : l'ON CONFLICT ne visant que
    // (patient_account_id, purpose), la unique_violation remontait en 500 permanent —
    // symptôme « soins-only ». #3624. On n'insère donc plus app_user_id.
    let row = sqlx::query(
        "INSERT INTO consent_record (patient_account_id, purpose, granted, granted_at, revoked_at)
         VALUES ($1, $2, $3,
                 CASE WHEN $3 THEN now() ELSE NULL END,
                 CASE WHEN NOT $3 THEN now() ELSE NULL END)
         ON CONFLICT (patient_account_id, purpose) DO UPDATE SET
           granted    = EXCLUDED.granted,
           -- Idempotent (#3876) : granted_at/revoked_at ne bougent que sur une
           -- vraie TRANSITION (révoqué→accordé ou accordé→révoqué), jamais sur
           -- une ré-affirmation de l'état déjà en place — sinon chaque PUT
           -- granted:true répété écrase l'horodatage RGPD de recueil d'origine
           -- (preuve légale du moment du consentement), en contradiction avec
           -- le contrat « Upsert idempotent » documenté ci-dessus.
           granted_at = CASE WHEN EXCLUDED.granted AND NOT consent_record.granted THEN now()
                              ELSE consent_record.granted_at END,
           revoked_at = CASE WHEN NOT EXCLUDED.granted AND consent_record.granted THEN now()
                              WHEN NOT EXCLUDED.granted THEN consent_record.revoked_at
                              ELSE NULL END
         RETURNING purpose, granted,
                   COALESCE(revoked_at, granted_at, created_at) AS updated_at",
    )
    .bind(claims.account_id)
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
///
/// `deny_unknown_fields` (#3839) : un opt-out de consentement ne doit jamais
/// être « accepté » (200) puis silencieusement jeté. Avant ce garde-fou, une
/// clé de canal inconnue ou mal orthographiée (ex. `push_prevention` — le
/// champ réel est `push_rappels`) était ignorée par serde sans erreur ; le
/// PATCH renvoyait 200 sans avoir rien changé, laissant croire à tort que
/// l'opt-out avait été pris en compte.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchNotificationPreferencesBody {
    email_rdv: Option<bool>,
    sms_rdv: Option<bool>,
    push_rdv: Option<bool>,
    email_messagerie: Option<bool>,
    push_messagerie: Option<bool>,
    email_rappels: Option<bool>,
    push_rappels: Option<bool>,
    email_documents: Option<bool>,
    push_documents: Option<bool>,
    email_paiement: Option<bool>,
    push_paiement: Option<bool>,
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
    email_documents: bool,
    push_documents: bool,
    email_paiement: bool,
    push_paiement: bool,
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
                email_rappels, push_rappels, \
                email_documents, push_documents, \
                email_paiement, push_paiement \
         FROM notification_preference \
         WHERE patient_account_id = $1 AND channel IS NULL AND type IS NULL",
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
            email_documents: true,
            push_documents: true,
            email_paiement: true,
            push_paiement: true,
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
            email_documents: r
                .try_get("email_documents")
                .map_err(|_| AppError::Internal)?,
            push_documents: r
                .try_get("push_documents")
                .map_err(|_| AppError::Internal)?,
            email_paiement: r
                .try_get("email_paiement")
                .map_err(|_| AppError::Internal)?,
            push_paiement: r.try_get("push_paiement").map_err(|_| AppError::Internal)?,
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
            email_messagerie, push_messagerie, email_rappels, push_rappels, \
            email_documents, push_documents, email_paiement, push_paiement) \
         VALUES ($1, \
           COALESCE($2, true), COALESCE($3, true), COALESCE($4, true), \
           COALESCE($5, true), COALESCE($6, true), COALESCE($7, true), COALESCE($8, true), \
           COALESCE($9, true), COALESCE($10, true), COALESCE($11, true), COALESCE($12, true)) \
         ON CONFLICT (patient_account_id) \
           WHERE channel IS NULL AND type IS NULL \
         DO UPDATE SET \
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
           email_documents  = CASE WHEN $9 IS NOT NULL THEN $9 \
                                   ELSE notification_preference.email_documents END, \
           push_documents   = CASE WHEN $10 IS NOT NULL THEN $10 \
                                   ELSE notification_preference.push_documents END, \
           email_paiement   = CASE WHEN $11 IS NOT NULL THEN $11 \
                                   ELSE notification_preference.email_paiement END, \
           push_paiement    = CASE WHEN $12 IS NOT NULL THEN $12 \
                                   ELSE notification_preference.push_paiement END, \
           updated_at       = now() \
         RETURNING email_rdv, sms_rdv, push_rdv, \
                   email_messagerie, push_messagerie, \
                   email_rappels, push_rappels, \
                   email_documents, push_documents, \
                   email_paiement, push_paiement",
    )
    .bind(claims.account_id)
    .bind(body.email_rdv)
    .bind(body.sms_rdv)
    .bind(body.push_rdv)
    .bind(body.email_messagerie)
    .bind(body.push_messagerie)
    .bind(body.email_rappels)
    .bind(body.push_rappels)
    .bind(body.email_documents)
    .bind(body.push_documents)
    .bind(body.email_paiement)
    .bind(body.push_paiement)
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
        email_documents: row
            .try_get("email_documents")
            .map_err(|_| AppError::Internal)?,
        push_documents: row
            .try_get("push_documents")
            .map_err(|_| AppError::Internal)?,
        email_paiement: row
            .try_get("email_paiement")
            .map_err(|_| AppError::Internal)?,
        push_paiement: row
            .try_get("push_paiement")
            .map_err(|_| AppError::Internal)?,
    }))
}

/// `GET /v1/account/consents` — liste les consentements RGPD du patient courant.
///
/// Lecture seule. Scoped par `patient_account_id = claims.account_id`.
/// RLS scoped par `app.current_account_id` (migration 0048).
/// Filtré au référentiel canonique [`CONSENT_PURPOSES`] (#3819) : une ligne
/// historique/hors-référentiel (ex. `data_processing`, runs QA antérieurs)
/// ne doit jamais être affichée `granted=true` sans pouvoir être retirée via
/// `PUT /account/consents/{purpose}`, qui n'accepte que ce même référentiel.
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
         WHERE patient_account_id = $1 AND purpose = ANY($2) \
         ORDER BY created_at ASC",
    )
    .bind(claims.account_id)
    .bind(&CONSENT_PURPOSES[..])
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
    /// #3860 : absents avant ce fix — `PatchDependentCoverageBody` les
    /// déclare et les écrit, mais la création les ignorait silencieusement
    /// (pas de deny_unknown_fields) : tiers_payant restait au défaut `false`
    /// et plateforme NULL, quelle que soit la valeur fournie au POST.
    plateforme: Option<String>,
    tiers_payant: Option<bool>,
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
/// Un lien actif existe déjà pour ce couple (guardian, nom+prénom+date de
/// naissance) → `409 duplicate_dependent` (#4475, dédup applicative).
pub async fn post_account_dependents(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PostDependentBody>,
) -> Result<(StatusCode, Json<PostDependentResponse>), AppError> {
    if !["enfant", "conjoint", "parent", "autre"].contains(&body.relationship.as_str()) {
        return Err(AppError::ValidationError);
    }

    if body.first_name.trim().is_empty() || body.last_name.trim().is_empty() {
        return Err(AppError::ValidationError);
    }

    let birth_date: Option<chrono::NaiveDate> = match body.birth_date.as_deref() {
        Some(s) => {
            let d: chrono::NaiveDate = s.parse().map_err(|_| AppError::ValidationError)?;
            if d > chrono::Utc::now().date_naive() {
                return Err(AppError::ValidationError);
            }
            Some(d)
        }
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

    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #5725 : le SELECT-puis-INSERT ci-dessous est une race TOCTOU sous
    // requêtes concurrentes (double-tap, retries réseau) — N requêtes pour
    // le même proche passent toutes le SELECT avant qu'aucun INSERT ne soit
    // visible. On sérialise via un verrou advisory transactionnel sur le
    // hash de l'identité (guardian + nom/prénom/date de naissance) : les
    // transactions concurrentes pour la même identité font la queue ici, et
    // seule la première voit encore "pas de doublon" au SELECT.
    let lock_key = format!(
        "{}|{}|{}|{}",
        claims.account_id,
        body.first_name.trim().to_lowercase(),
        body.last_name.trim().to_lowercase(),
        birth_date.map(|d| d.to_string()).unwrap_or_default(),
    );
    sqlx::query("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))")
        .bind(&lock_key)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // #4475 : dependent_account_id est toujours neuf à la création, donc
    // l'index unique account_guardianship_active_pair_uidx (couple actif)
    // ne peut structurellement jamais matcher — un double-submit du même
    // proche (même nom/prénom/date de naissance) mintait un second compte
    // géré identique. Contrôle applicatif avant l'INSERT : lien actif déjà
    // existant pour ce couple (guardian, identité) → 409, pas de doublon.
    // birth_date comparé via IS NOT DISTINCT FROM (NULL-safe : deux proches
    // sans date de naissance renseignée comptent comme le même couple).
    let duplicate = sqlx::query(
        "SELECT 1 FROM account_guardianship ag \
         JOIN patient_account pa ON pa.id = ag.dependent_account_id \
         WHERE ag.guardian_account_id = $1 AND ag.active = true \
           AND pa.first_name = $2 AND pa.last_name = $3 \
           AND pa.birth_date IS NOT DISTINCT FROM $4",
    )
    .bind(claims.account_id)
    .bind(&body.first_name)
    .bind(&body.last_name)
    .bind(birth_date)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if duplicate.is_some() {
        return Err(AppError::DuplicateDependent);
    }

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
        if let Some(ref regime) = cov.regime_obligatoire {
            if !["regime_general", "ame", "css"].contains(&regime.as_str()) {
                return Err(AppError::ValidationError);
            }
        }
        validate_coverage_field_non_empty(&cov.amc)?;
        validate_coverage_field_non_empty(&cov.numero_adherent)?;
        // #4312 : même contrôle de format que patch_account_coverage
        // (couverture personnelle) — un NSS malformé n'était accepté (201)
        // que côté dépendant, jamais côté soi (422).
        validate_nss(&cov.nss)?;

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
               (patient_account_id, regime_obligatoire, nss_encrypted, amc, numero_adherent, \
                plateforme, tiers_payant) \
             VALUES ($1, $2, $3, $4, $5, $6, COALESCE($7, false)) \
             ON CONFLICT (patient_account_id) DO UPDATE SET \
               regime_obligatoire = COALESCE($2, patient_coverage.regime_obligatoire), \
               nss_encrypted      = COALESCE($3, patient_coverage.nss_encrypted), \
               amc                = COALESCE($4, patient_coverage.amc), \
               numero_adherent    = COALESCE($5, patient_coverage.numero_adherent), \
               plateforme         = COALESCE($6, patient_coverage.plateforme), \
               tiers_payant       = COALESCE($7, patient_coverage.tiers_payant), \
               updated_at         = now()",
        )
        .bind(dependent_account_id)
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
        Some(s) => {
            let d: chrono::NaiveDate = s.parse().map_err(|_| AppError::ValidationError)?;
            if d > chrono::Utc::now().date_naive() {
                return Err(AppError::ValidationError);
            }
            Some(d)
        }
        None => None,
    };

    if let Some(ref rel) = body.relationship {
        if !["enfant", "conjoint", "parent", "autre"].contains(&rel.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    if body
        .first_name
        .as_deref()
        .is_some_and(|s| s.trim().is_empty())
        || body
            .last_name
            .as_deref()
            .is_some_and(|s| s.trim().is_empty())
    {
        return Err(AppError::ValidationError);
    }

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
        if let Some(ref regime) = cov.regime_obligatoire {
            if !["regime_general", "ame", "css"].contains(&regime.as_str()) {
                return Err(AppError::ValidationError);
            }
        }
        validate_coverage_field_non_empty(&cov.amc)?;
        validate_coverage_field_non_empty(&cov.numero_adherent)?;
        // #4312 : même contrôle de format que patch_account_coverage
        // (couverture personnelle) — un NSS malformé n'était accepté (200)
        // que côté dépendant, jamais côté soi (422).
        validate_nss(&cov.nss)?;

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
/// Cascade (#5679) : annule d'abord les RDV futurs actifs (`requested`/`confirmed`) du
/// dépendant et libère leurs créneaux — sinon ils restent orphelins (créneau tenu, cabinet
/// les voit toujours, tuteur perd tout accès dès la tutelle inactive, RLS §07).
/// Audité : `action:'revoke_guardianship'` (§07 §10) + `'cancel_appointment'` par RDV annulé.
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

    // Cascade AVANT la révocation : appointment_patient_read (migration 0196) exige la
    // tutelle encore `active = true` pour voir les RDV du dépendant — désactiver
    // account_guardianship en premier rendrait ces RDV illisibles dans CETTE même
    // transaction (read-your-own-writes) avant même de pouvoir les annuler.
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let pending_appointments = sqlx::query(
        "SELECT a.id, a.cabinet_id, a.slot_id \
         FROM appointment a \
         JOIN patient p ON p.id = a.patient_id \
         WHERE p.patient_account_id = $1 \
           AND a.status IN ('requested', 'confirmed') \
           AND a.starts_at > now() \
           AND a.deleted_at IS NULL",
    )
    .bind(dependent_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    for appt_row in pending_appointments {
        let appt_id: Uuid = appt_row.try_get("id").map_err(|_| AppError::Internal)?;
        let appt_cabinet_id: Uuid = appt_row
            .try_get("cabinet_id")
            .map_err(|_| AppError::Internal)?;
        let appt_slot_id: Option<Uuid> = appt_row
            .try_get("slot_id")
            .map_err(|_| AppError::Internal)?;

        sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
            .bind(appt_cabinet_id.to_string())
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

        sqlx::query(
            "UPDATE appointment \
             SET status = 'cancelled', cancelled_at = now(), \
                 cancel_reason = 'dependent_removed', updated_at = now() \
             WHERE id = $1",
        )
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        // Libération du créneau : best-effort, isolée dans un savepoint — même pattern
        // que cancel_appointment (#5392) : un AUTRE créneau peut déjà chevaucher la
        // plage et faire violer l'exclusion (23P01), sans que ça doive faire échouer
        // la suppression du dépendant.
        if let Some(sid) = appt_slot_id {
            let mut savepoint = tx.begin().await.map_err(|_| AppError::Internal)?;
            let release = sqlx::query("UPDATE availability_slot SET status = 'open' WHERE id = $1")
                .bind(sid)
                .execute(&mut *savepoint)
                .await;
            match release {
                Ok(_) => savepoint.commit().await.map_err(|_| AppError::Internal)?,
                Err(e) if is_exclusion_violation(&e) => {
                    savepoint.rollback().await.map_err(|_| AppError::Internal)?
                }
                Err(_) => return Err(AppError::Internal),
            }
        }

        sqlx::query(
            "INSERT INTO audit_log \
             (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
             VALUES ($1, $2, 'patient', 'cancel_appointment', 'appointment', $3)",
        )
        .bind(appt_cabinet_id)
        .bind(claims.sub)
        .bind(appt_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        tracing::info!(
            guardian_account_id = %claims.account_id,
            dependent_account_id = %dependent_id,
            appointment_id = %appt_id,
            "dependent's future appointment cancelled on guardianship revocation"
        );
    }

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
///
/// RBAC : soumission sur le profil provider de l'APPELANT (`user_id = sub`) ; réservé
/// aux rôles `practitioner`/`admin` (cohérent avec le GET, cf. #3412).
pub async fn pro_verification(
    State(state): State<AppState>,
    Extension(dispatcher): Extension<Arc<dyn JobDispatcher>>,
    claims: ProPractitionerClaims,
    Json(body): Json<ProVerificationBody>,
) -> Result<(StatusCode, Json<ProVerificationResponse>), AppError> {
    if body.id_type != "rpps" && body.id_type != "adeli" {
        return Err(AppError::ValidationError);
    }

    // Validation de format réglementaire (norme ADELI/RPPS française) : RPPS = 11
    // chiffres, ADELI = 9 chiffres. Rejette avant toute insertion `pending`.
    let expected_len = if body.id_type == "rpps" { 11 } else { 9 };
    if body.identifier.len() != expected_len || !body.identifier.chars().all(|c| c.is_ascii_digit())
    {
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

// ── Avatar du compte patient (GET/PUT /v1/account/avatar) ───────────────────

/// Corps de `PUT /v1/account/avatar`.
#[derive(Deserialize)]
pub struct PutAvatarBody {
    /// Type MIME (`image/jpeg`, `image/png`, `image/webp`).
    mime: String,
    /// Image encodée base64 (≤ 300 Ko décodés).
    data_base64: String,
}

const AVATAR_MAX_BYTES: usize = 300 * 1024;
const AVATAR_MIMES: [&str; 3] = ["image/jpeg", "image/png", "image/webp"];

/// Vérifie que `bytes` commence par la signature (« magic bytes ») attendue
/// pour `mime` (#3820) : seuls le MIME déclaré et la taille étaient
/// contrôlés, un contenu arbitraire (ex. texte brut) était accepté et
/// reservi tel quel avec `Content-Type: image/<mime>`. `mime` est déjà
/// vérifié appartenir à [`AVATAR_MIMES`] par l'appelant.
fn has_valid_image_signature(mime: &str, bytes: &[u8]) -> bool {
    match mime {
        "image/png" => bytes.starts_with(b"\x89PNG\r\n\x1a\n"),
        "image/jpeg" => bytes.starts_with(b"\xff\xd8\xff"),
        "image/webp" => bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP",
        _ => false,
    }
}

/// `PUT /v1/account/avatar` — pose la photo de profil du compte patient.
///
/// Token `kind:"patient"` requis. RLS `account_self_update` via
/// `app.current_account_id`. MIME hors liste, signature (magic bytes)
/// incohérente avec le MIME déclaré, ou image > 300 Ko → 422.
pub async fn put_account_avatar(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PutAvatarBody>,
) -> Result<StatusCode, AppError> {
    if !AVATAR_MIMES.contains(&body.mime.as_str()) {
        return Err(AppError::ValidationError);
    }
    use base64::Engine as _;
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(body.data_base64.trim())
        .map_err(|_| AppError::ValidationError)?;
    if bytes.is_empty() || bytes.len() > AVATAR_MAX_BYTES {
        return Err(AppError::ValidationError);
    }
    if !has_valid_image_signature(&body.mime, &bytes) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let updated = sqlx::query(
        "UPDATE patient_account SET avatar = $1, avatar_mime = $2, updated_at = now() \
         WHERE id = $3 AND deleted_at IS NULL",
    )
    .bind(&bytes)
    .bind(&body.mime)
    .bind(claims.account_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }
    Ok(StatusCode::NO_CONTENT)
}

/// `GET /v1/account/avatar` — photo de profil du compte patient.
///
/// 200 avec les octets + Content-Type, 404 si aucun avatar.
pub async fn get_account_avatar(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<axum::response::Response, AppError> {
    use axum::response::IntoResponse;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "SELECT avatar, avatar_mime FROM patient_account \
         WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(claims.account_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let _ = tx.rollback().await;

    let avatar: Option<Vec<u8>> = row.try_get("avatar").map_err(|_| AppError::Internal)?;
    let mime: Option<String> = row.try_get("avatar_mime").map_err(|_| AppError::Internal)?;
    match (avatar, mime) {
        (Some(bytes), Some(mime)) => Ok((
            StatusCode::OK,
            [(axum::http::header::CONTENT_TYPE, mime)],
            bytes,
        )
            .into_response()),
        _ => Err(AppError::NotFound),
    }
}

// ---------------------------------------------------------------------------
// Invitation d'un proche adulte (#6119) — `/v1/account/access-requests*`.
//
// Distinct de `account/dependents` (compte géré sans mot de passe, pour un
// mineur) : ici le proche invité a déjà (ou aura) son propre compte, et
// n'obtient qu'un accès en lecture au périmètre choisi par l'invitant sur SES
// propres données, après acceptation.
//
// `invitee_account_id` reste NULL tant que l'invité n'a pas agi : il n'est
// résolu qu'au moment d'`accept`/`refuse`, à partir du compte authentifié qui
// appelle la route en connaissant l'`id` de la demande (reçu hors-bande,
// notification/deep-link — cf. `IncomingRequestCubit.load`, pas de route de
// liste côté invité dans ce lot de 7 endpoints). C'est pourquoi la RLS de
// `account_access_request` (migration 0239) est ouverte pour `nubia_app` et
// le filtrage se fait ici, dans chaque `WHERE`.
// ---------------------------------------------------------------------------

const ACCESS_REQUEST_RELATIONSHIPS: [&str; 3] = ["enfant", "conjoint", "autre"];
const ACCESS_REQUEST_SCOPE_VALUES: [&str; 4] =
    ["rendez_vous", "documents", "ordonnances", "dossier_medical"];

/// Une demande d'accès, telle que renvoyée par les 7 endpoints
/// `/v1/account/access-requests*`.
#[derive(Serialize)]
pub struct AccessRequestResponse {
    id: Uuid,
    first_name: String,
    last_name: String,
    relationship: String,
    status: String,
    channel: String,
    scope: Vec<String>,
    sent_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    revoked_at: Option<String>,
}

fn access_request_from_row(row: &sqlx::postgres::PgRow) -> Result<AccessRequestResponse, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
    let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
    let relationship: String = row
        .try_get("relationship")
        .map_err(|_| AppError::Internal)?;
    let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
    let channel: String = row.try_get("channel").map_err(|_| AppError::Internal)?;
    let scope: Vec<String> = row.try_get("scope").map_err(|_| AppError::Internal)?;
    let sent_at: chrono::DateTime<chrono::Utc> =
        row.try_get("sent_at").map_err(|_| AppError::Internal)?;
    let revoked_at: Option<chrono::DateTime<chrono::Utc>> =
        row.try_get("revoked_at").map_err(|_| AppError::Internal)?;
    Ok(AccessRequestResponse {
        id,
        first_name,
        last_name,
        relationship,
        status,
        channel,
        scope,
        sent_at: sent_at.to_rfc3339(),
        revoked_at: revoked_at.map(|t| t.to_rfc3339()),
    })
}

/// `GET /v1/account/access-requests` — demandes envoyées par le compte
/// courant, tous statuts confondus (hors demandes annulées, `cancelled_at`
/// agit comme un soft-delete — même logique que `active=false` sur
/// `account_guardianship`).
pub async fn get_account_access_requests(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<Vec<AccessRequestResponse>>, AppError> {
    let rows = sqlx::query(
        "SELECT id, first_name, last_name, relationship, status, channel, scope, sent_at, revoked_at \
         FROM account_access_request \
         WHERE requester_account_id = $1 AND cancelled_at IS NULL \
         ORDER BY sent_at DESC",
    )
    .bind(claims.account_id)
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let requests = rows
        .iter()
        .map(access_request_from_row)
        .collect::<Result<Vec<_>, AppError>>()?;

    tracing::info!(
        account_id = %claims.account_id,
        count = requests.len(),
        "access requests listed"
    );

    Ok(Json(requests))
}

/// Corps de la requête `POST /v1/account/access-requests`.
#[derive(Deserialize)]
pub struct PostAccessRequestBody {
    first_name: String,
    last_name: String,
    relationship: String,
    channel: String,
    #[serde(default)]
    scope: Vec<String>,
    email: Option<String>,
    phone: Option<String>,
}

/// `POST /v1/account/access-requests` — invite un proche adulte
/// (conjoint/autre) avec le périmètre de droits accordé.
///
/// Un lien actif (`envoyee`/`acceptee`, ni annulé ni révoqué) existe déjà pour
/// ce couple (requester, email/téléphone) → `409 duplicate_access_request`
/// (même anti-doublon applicatif que `POST /v1/account/dependents`, #4475).
pub async fn post_account_access_requests(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Json(body): Json<PostAccessRequestBody>,
) -> Result<(StatusCode, Json<AccessRequestResponse>), AppError> {
    if body.first_name.trim().is_empty() || body.last_name.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    if !ACCESS_REQUEST_RELATIONSHIPS.contains(&body.relationship.as_str()) {
        return Err(AppError::ValidationError);
    }
    if !["email", "sms"].contains(&body.channel.as_str()) {
        return Err(AppError::ValidationError);
    }
    for right in &body.scope {
        if !ACCESS_REQUEST_SCOPE_VALUES.contains(&right.as_str()) {
            return Err(AppError::ValidationError);
        }
    }

    let email = match body.email.as_deref().map(str::trim) {
        Some(e) if !e.is_empty() => {
            if !is_valid_email_format(e) {
                return Err(AppError::ValidationError);
            }
            Some(e.to_lowercase())
        }
        _ => None,
    };
    let phone = match body.phone.as_deref().map(str::trim) {
        Some(p) if !p.is_empty() => Some(p.to_string()),
        _ => None,
    };
    match body.channel.as_str() {
        "email" if email.is_none() => return Err(AppError::ValidationError),
        "sms" if phone.is_none() => return Err(AppError::ValidationError),
        _ => {}
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    let duplicate = sqlx::query(
        "SELECT 1 FROM account_access_request \
         WHERE requester_account_id = $1 AND status IN ('envoyee', 'acceptee') \
           AND cancelled_at IS NULL AND revoked_at IS NULL \
           AND ((email IS NOT NULL AND email = $2) OR (phone IS NOT NULL AND phone = $3))",
    )
    .bind(claims.account_id)
    .bind(&email)
    .bind(&phone)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if duplicate.is_some() {
        return Err(AppError::DuplicateAccessRequest);
    }

    let row = sqlx::query(
        "INSERT INTO account_access_request \
           (requester_account_id, first_name, last_name, relationship, channel, email, phone, scope) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) \
         RETURNING id, first_name, last_name, relationship, status, channel, scope, sent_at, revoked_at",
    )
    .bind(claims.account_id)
    .bind(&body.first_name)
    .bind(&body.last_name)
    .bind(&body.relationship)
    .bind(&body.channel)
    .bind(&email)
    .bind(&phone)
    .bind(&body.scope)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let response = access_request_from_row(&row)?;

    tracing::info!(
        account_id = %claims.account_id,
        access_request_id = %response.id,
        channel = %body.channel,
        "access request sent"
    );

    Ok((StatusCode::CREATED, Json(response)))
}

/// `POST /v1/account/access-requests/{id}/resend` — relance une demande
/// `envoyee` (renvoi du canal, pas de changement de périmètre). Demande
/// inconnue, déjà décidée ou annulée → `404` (anti-énumération, §07 §2.9).
pub async fn post_account_access_request_resend(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(request_id): Path<Uuid>,
) -> Result<Json<AccessRequestResponse>, AppError> {
    let row = sqlx::query(
        "UPDATE account_access_request \
         SET sent_at = now(), updated_at = now() \
         WHERE id = $1 AND requester_account_id = $2 \
           AND status = 'envoyee' AND cancelled_at IS NULL \
         RETURNING id, first_name, last_name, relationship, status, channel, scope, sent_at, revoked_at",
    )
    .bind(request_id)
    .bind(claims.account_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let response = access_request_from_row(&row)?;

    tracing::info!(
        account_id = %claims.account_id,
        access_request_id = %request_id,
        "access request resent"
    );

    Ok(Json(response))
}

/// `DELETE /v1/account/access-requests/{id}` — annule une demande `envoyee`,
/// côté invitant. Soft-delete (`cancelled_at`), jamais de `DELETE` SQL (§07
/// §10) : exclue de `GET /v1/account/access-requests` ensuite. Demande
/// inconnue, déjà décidée ou déjà annulée → `404`.
pub async fn delete_account_access_request(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(request_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let updated = sqlx::query(
        "UPDATE account_access_request \
         SET cancelled_at = now(), updated_at = now() \
         WHERE id = $1 AND requester_account_id = $2 \
           AND status = 'envoyee' AND cancelled_at IS NULL",
    )
    .bind(request_id)
    .bind(claims.account_id)
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    tracing::info!(
        account_id = %claims.account_id,
        access_request_id = %request_id,
        "access request cancelled"
    );

    Ok(StatusCode::NO_CONTENT)
}

/// Résout une demande `envoyee` en `acceptee`/`refusee` côté invité : lie
/// `invitee_account_id` au compte courant s'il n'est pas encore établi, sinon
/// vérifie qu'il correspond déjà (une demande ne peut être réclamée que par
/// un seul invité). Un titulaire ne peut pas décider sur sa propre demande
/// envoyée (`requester_account_id <> $2`). Aucune ligne → `404`
/// (anti-énumération, §07 §2.9 — vaut aussi bien pour un `id` inconnu qu'une
/// demande déjà décidée/annulée ou déjà réclamée par un autre invité).
async fn decide_access_request(
    state: &AppState,
    claims: &PatientAccountClaims,
    request_id: Uuid,
    new_status: &str,
) -> Result<AccessRequestResponse, AppError> {
    let row = sqlx::query(
        "UPDATE account_access_request \
         SET status = $3, invitee_account_id = COALESCE(invitee_account_id, $2), \
             decided_at = now(), updated_at = now() \
         WHERE id = $1 AND status = 'envoyee' AND cancelled_at IS NULL \
           AND requester_account_id <> $2 \
           AND (invitee_account_id IS NULL OR invitee_account_id = $2) \
         RETURNING id, first_name, last_name, relationship, status, channel, scope, sent_at, revoked_at",
    )
    .bind(request_id)
    .bind(claims.account_id)
    .bind(new_status)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    access_request_from_row(&row)
}

/// `POST /v1/account/access-requests/{id}/accept` — accepte une invitation
/// reçue, côté invité.
pub async fn post_account_access_request_accept(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(request_id): Path<Uuid>,
) -> Result<Json<AccessRequestResponse>, AppError> {
    let response = decide_access_request(&state, &claims, request_id, "acceptee").await?;

    tracing::info!(
        invitee_account_id = %claims.account_id,
        access_request_id = %request_id,
        "access request accepted"
    );

    Ok(Json(response))
}

/// `POST /v1/account/access-requests/{id}/refuse` — refuse une invitation
/// reçue, côté invité.
pub async fn post_account_access_request_refuse(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(request_id): Path<Uuid>,
) -> Result<Json<AccessRequestResponse>, AppError> {
    let response = decide_access_request(&state, &claims, request_id, "refusee").await?;

    tracing::info!(
        invitee_account_id = %claims.account_id,
        access_request_id = %request_id,
        "access request refused"
    );

    Ok(Json(response))
}

/// `POST /v1/account/access-requests/{id}/revoke` — révoque un accès déjà
/// accordé, côté invité. Distinct de `DELETE /v1/account/dependents/{id}`,
/// qui reste la révocation côté gestionnaire d'un dépendant enfant. Demande
/// inconnue, jamais acceptée par ce compte, ou déjà révoquée → `404`.
pub async fn post_account_access_request_revoke(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Path(request_id): Path<Uuid>,
) -> Result<StatusCode, AppError> {
    let updated = sqlx::query(
        "UPDATE account_access_request \
         SET revoked_at = now(), updated_at = now() \
         WHERE id = $1 AND invitee_account_id = $2 \
           AND status = 'acceptee' AND revoked_at IS NULL",
    )
    .bind(request_id)
    .bind(claims.account_id)
    .execute(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    if updated.rows_affected() == 0 {
        return Err(AppError::NotFound);
    }

    tracing::info!(
        invitee_account_id = %claims.account_id,
        access_request_id = %request_id,
        "access revoked by invitee"
    );

    Ok(StatusCode::NO_CONTENT)
}
