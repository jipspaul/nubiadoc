//! Route publique : GET /v1/cabinets/:id/info (US-P28).
//! Aucun JWT requis. Si un token patient valide est présent, enrichit avec `is_current_patient`.

use axum::{
    extract::{Path, State},
    http::HeaderMap,
    Json,
};
use jsonwebtoken::{decode, DecodingKey, Validation};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{auth::AppError, AppState};

#[derive(Serialize)]
pub struct ProviderInfo {
    pub display_name: String,
    pub specialty: Option<String>,
    pub languages: Option<Vec<String>>,
    pub pmr: Option<bool>,
    pub teleconsult: Option<bool>,
    pub bio: Option<String>,
    pub photo_url: Option<String>,
}

#[derive(Serialize)]
pub struct AccessInfo {
    pub door_code: Option<String>,
    pub parking: Option<String>,
    pub pmr: Option<bool>,
}

#[derive(Serialize)]
pub struct CabinetInfoResponse {
    pub id: Uuid,
    pub name: String,
    pub address: Option<serde_json::Value>,
    pub geo: Option<serde_json::Value>,
    pub contact: Option<serde_json::Value>,
    pub hours: Option<serde_json::Value>,
    pub provider: Option<ProviderInfo>,
    pub access: Option<AccessInfo>,
    pub is_current_patient: Option<bool>,
}

/// Claims minimaux pour détecter un token patient (extraction optionnelle).
#[derive(Deserialize)]
struct OptionalPatientClaims {
    kind: String,
    account_id: Option<Uuid>,
}

/// Extrait `account_id` depuis le header `Authorization: Bearer <token>` si le token
/// est valide et de kind `"patient"`. Renvoie `None` sinon (token absent, invalide,
/// expiré ou non-patient) — route publique, pas de rejet.
fn extract_patient_account_id(headers: &HeaderMap, jwt_secret: &str) -> Option<Uuid> {
    let auth = headers.get("Authorization")?.to_str().ok()?;
    let token = auth.strip_prefix("Bearer ")?;
    let key = DecodingKey::from_secret(jwt_secret.as_bytes());
    let mut validation = Validation::default();
    validation.validate_exp = true;
    let claims = decode::<OptionalPatientClaims>(token, &key, &validation)
        .ok()?
        .claims;
    if claims.kind != "patient" {
        return None;
    }
    claims.account_id
}

/// `GET /v1/cabinets/:id/info` — infos pratiques publiques d'un cabinet (US-P28).
///
/// Route publique, pas de JWT obligatoire. Cabinet inconnu → `404`.
/// Enrichit avec `is_current_patient: true/false` si un token patient valide est présent.
pub async fn get_cabinet_info(
    State(state): State<AppState>,
    Path(cabinet_id): Path<Uuid>,
    headers: HeaderMap,
) -> Result<Json<CabinetInfoResponse>, AppError> {
    // Lecture directe sur `cabinet` — table plateforme accessible sans RLS cabinet
    // (lire le commentaire : la policy `tenant_isolation` sur `cabinet` utilise `id = GUC`,
    // donc on doit poser le GUC pour que la RLS passe en lecture).
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cab_row = sqlx::query(
        "SELECT id, raison_sociale, settings FROM cabinet WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let id: Uuid = cab_row.try_get("id").map_err(|_| AppError::Internal)?;
    let name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let settings: serde_json::Value = cab_row
        .try_get("settings")
        .map_err(|_| AppError::Internal)?;

    let address = settings.get("address").cloned();
    let geo = settings.get("geo").cloned();
    let contact = settings.get("contact").cloned();
    let hours = settings.get("hours").cloned();
    let access_door_code = settings
        .get("door_code")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    let access_parking = settings
        .get("parking")
        .and_then(|v| v.as_str())
        .map(|s| s.to_owned());
    let access_pmr = settings.get("pmr_access").and_then(|v| v.as_bool());

    // Récupère le provider lié au cabinet (premier praticien listé ou propriétaire).
    let prov_row = sqlx::query(
        "SELECT display_name, specialite, languages, pmr, teleconsult, bio, photo_key \
         FROM provider \
         WHERE cabinet_id = $1 \
         ORDER BY is_listed DESC, created_at ASC \
         LIMIT 1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let provider = prov_row.map(|r| {
        let photo_key: Option<String> = r.try_get("photo_key").unwrap_or(None);
        ProviderInfo {
            display_name: r.try_get("display_name").unwrap_or_default(),
            specialty: r.try_get("specialite").unwrap_or(None),
            languages: r.try_get("languages").unwrap_or(None),
            pmr: r.try_get("pmr").unwrap_or(None),
            teleconsult: r.try_get("teleconsult").unwrap_or(None),
            bio: r.try_get("bio").unwrap_or(None),
            // Stub URL : le signer réel est injecté via Extension dans les routes documentées.
            // Pour cette route publique on génère une URL simple depuis photo_key si présent.
            photo_url: photo_key.map(|k| format!("https://storage.stub/{k}")),
        }
    });

    let access = Some(AccessInfo {
        door_code: access_door_code,
        parking: access_parking,
        pmr: access_pmr,
    });

    // Enrichissement optionnel : is_current_patient si token patient valide fourni.
    let is_current_patient =
        if let Some(account_id) = extract_patient_account_id(&headers, &state.jwt_secret) {
            let exists = sqlx::query(
                "SELECT 1 FROM patient \
                 WHERE cabinet_id = $1 AND patient_account_id = $2 AND deleted_at IS NULL",
            )
            .bind(cabinet_id)
            .bind(account_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            Some(exists.is_some())
        } else {
            None
        };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %cabinet_id,
        is_current_patient = ?is_current_patient,
        "cabinet info queried"
    );

    Ok(Json(CabinetInfoResponse {
        id,
        name,
        address,
        geo,
        contact,
        hours,
        provider,
        access,
        is_current_patient,
    }))
}
