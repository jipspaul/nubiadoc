//! Structs et helpers de réponse partagés par les handlers `appointments_*`
//! (`appointments_actions.rs`, `appointments_read.rs`, `appointments_create.rs`)
//! — extrait de `appointments.rs` (refactor pur, aucun changement de
//! comportement, issue #4329) : `appointments.rs` dépassait largement le
//! plafond absolu de 700 lignes fixé par CLAUDE.md.
//!
//! Regroupe ici ce qui est utilisé par PLUSIEURS des handlers désormais
//! éclatés entre les trois modules ci-dessus : `AppointmentDetail`/
//! `ProviderDetail`/`CabinetInfo` (réponse commune à `PATCH`/`GET`/`POST`
//! d'un RDV), les helpers de fetch `fetch_provider_for_response`/
//! `fetch_cabinet_for_response`, la détection de violation de contrainte
//! d'exclusion `is_exclusion_violation` (créneau déjà pris, SQLSTATE
//! `23P01`) et le formatage d'adresse `format_establishment_address`
//! (fallback annuaire, utilisé par `fetch_cabinet_for_response` ci-dessous
//! ET par les lectures enrichies de `appointments_read.rs`).

use serde::Serialize;
use sqlx::Row;
use uuid::Uuid;

use crate::auth::AppError;

#[derive(Serialize)]
pub struct ProviderDetail {
    pub id: Option<Uuid>,
    pub display_name: Option<String>,
    pub specialty: Option<String>,
}

#[derive(Serialize)]
pub struct CabinetInfo {
    pub name: String,
    pub address: Option<String>,
}

/// Identité du bénéficiaire d'un RDV — soi-même (`is_self: true`, pas de nom
/// exposé, redondant avec le compte en session) ou un dépendant (#5563 :
/// jusqu'ici, un RDV pris `on_behalf_of` un dépendant (`appointments_create.rs`)
/// était rendu indiscernable d'un RDV du tuteur en lecture, alors que la RLS
/// de tutelle (migration 0196) fait bien remonter les deux dans les mêmes
/// endpoints).
#[derive(Serialize)]
pub struct BeneficiarySummary {
    pub account_id: Option<Uuid>,
    pub is_self: bool,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
}

#[derive(Serialize)]
pub struct AppointmentDetail {
    pub id: Uuid,
    pub starts_at: String,
    pub ends_at: String,
    pub status: String,
    pub motif: Option<String>,
    pub provider: ProviderDetail,
    pub cabinet: CabinetInfo,
    pub beneficiary: BeneficiarySummary,
    /// #3845 : restitue la demande de rappel (voir AppointmentItem).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub callback_requested_at: Option<String>,
}

/// Formate l'adresse jsonb `establishment.address` (`{"rue":...,"cp":...,"ville":...}`,
/// cf. `db/migrations/0040_marketplace_provider_seed.sql`) en une ligne affichable /
/// utilisable comme destination de navigation.
pub(crate) fn format_establishment_address(address: &serde_json::Value) -> Option<String> {
    let rue = address.get("rue").and_then(|v| v.as_str());
    let cp = address.get("cp").and_then(|v| v.as_str());
    let ville = address.get("ville").and_then(|v| v.as_str());

    let cp_ville = match (cp, ville) {
        (Some(cp), Some(ville)) => Some(format!("{cp} {ville}")),
        (Some(cp), None) => Some(cp.to_string()),
        (None, Some(ville)) => Some(ville.to_string()),
        (None, None) => None,
    };

    let parts: Vec<String> = [rue.map(str::to_string), cp_ville]
        .into_iter()
        .flatten()
        .collect();

    if parts.is_empty() {
        None
    } else {
        Some(parts.join(", "))
    }
}

pub(crate) fn is_exclusion_violation(e: &sqlx::Error) -> bool {
    matches!(
        e,
        sqlx::Error::Database(db_err) if db_err.code().as_deref() == Some("23P01")
    )
}

pub(crate) async fn fetch_provider_for_response(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    practitioner_id: Uuid,
) -> Result<(Option<Uuid>, Option<String>, Option<String>), AppError> {
    let row = sqlx::query(
        "SELECT id, display_name, specialite FROM provider \
         WHERE practitioner_id = $1 LIMIT 1",
    )
    .bind(practitioner_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;

    Ok(match row {
        Some(r) => {
            let pid: Uuid = r.try_get("id").map_err(|_| AppError::Internal)?;
            let dn: String = r.try_get("display_name").map_err(|_| AppError::Internal)?;
            let sp: Option<String> = r.try_get("specialite").map_err(|_| AppError::Internal)?;
            (Some(pid), Some(dn), sp)
        }
        None => (None, None, None),
    })
}

/// Résout le bénéficiaire (soi-même vs quel dépendant) depuis
/// `patient.patient_account_id` (#5563) — comparé au compte en session
/// (`session_account_id`, toujours le tuteur/patient connecté, jamais le
/// dépendant). `patient.first_name`/`last_name` sont resynchronisés depuis
/// `patient_account` par `ensure_patient_for_cabinet` (migration 0155), donc
/// fiables comme nom d'affichage sans requête supplémentaire sur
/// `patient_account`. Aucun nom exposé quand `is_self` (redondant).
pub(crate) async fn fetch_beneficiary_for_response(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    patient_id: Uuid,
    session_account_id: Uuid,
) -> Result<BeneficiarySummary, AppError> {
    let row =
        sqlx::query("SELECT patient_account_id, first_name, last_name FROM patient WHERE id = $1")
            .bind(patient_id)
            .fetch_optional(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let (account_id, first_name, last_name) = match row {
        Some(r) => {
            let account_id: Option<Uuid> = r
                .try_get("patient_account_id")
                .map_err(|_| AppError::Internal)?;
            let first_name: String = r.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = r.try_get("last_name").map_err(|_| AppError::Internal)?;
            (account_id, Some(first_name), Some(last_name))
        }
        None => (None, None, None),
    };

    let is_self = account_id == Some(session_account_id);

    Ok(BeneficiarySummary {
        account_id,
        is_self,
        first_name: if is_self { None } else { first_name },
        last_name: if is_self { None } else { last_name },
    })
}

pub(crate) async fn fetch_cabinet_for_response(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    practitioner_id: Uuid,
) -> Result<(String, Option<String>), AppError> {
    let row = sqlx::query(
        "SELECT raison_sociale, settings->>'address' AS address FROM cabinet WHERE id = $1",
    )
    .bind(cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;

    let name: String = row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let address: Option<String> = row.try_get("address").map_err(|_| AppError::Internal)?;

    // Fallback establishment quand `cabinet.settings` ne porte pas d'adresse
    // (cas du cabinet seed — #3557), déjà appliqué à preparation/directions
    // mais pas ici : détail/create/patch renvoyaient `address: null` (#3799).
    let address = if address.is_some() {
        address
    } else {
        let est_row = sqlx::query(
            "SELECT e.address AS establishment_address \
             FROM provider p \
             LEFT JOIN establishment e ON e.id = p.establishment_id \
             WHERE p.practitioner_id = $1 \
             LIMIT 1",
        )
        .bind(practitioner_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        est_row
            .and_then(|r| {
                r.try_get::<Option<serde_json::Value>, _>("establishment_address")
                    .ok()
                    .flatten()
            })
            .as_ref()
            .and_then(format_establishment_address)
    };

    Ok((name, address))
}
