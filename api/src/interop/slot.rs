//! `GET /v1/interop/fhir/Slot/:id`, `GET /v1/interop/fhir/Slot` (recherche) et
//! `GET /v1/interop/fhir/Schedule/:id` — lecture seule (lot A3).
//!
//! Toutes ces routes exigent le scope `slots:read` (`require_scope`) et lisent
//! via `with_tenant` (GUC `app.current_cabinet_id`), **avec en plus** un
//! filtre `WHERE cabinet_id = $n` explicite dans chaque requête : la table
//! `practitioner` n'a aucune policy RLS (vérifié dans les migrations), donc le
//! filtre explicite n'est pas de la ceinture-et-bretelles ici, c'est la seule
//! barrière pour `Schedule`. Aucune écriture sur `availability_slot` — la
//! réservation (`Appointment`) est un lot séparé (A6).
//!
//! Choix de recherche `Slot` : un couple `from`/`to` (ISO 8601, bornes sur
//! `starts_at`) plutôt que la syntaxe de comparateur FHIR `start=ge...`—
//! plus simple à parser correctement pour cette première tranche, et déjà le
//! choix retenu par l'endpoint BO équivalent (`list_cabinet_slots`,
//! `api/src/scheduling.rs`). Résultat borné à `MAX_SEARCH_RESULTS` (pas de
//! paramètre `limit`/`_count` exposé pour l'instant — cf. #3516, l'endpoint
//! BO avait dû être corrigé après coup pour ne pas renvoyer tout le cabinet).

use axum::{
    extract::{Path, Query, State},
    Json,
};
use chrono::{DateTime, Utc};
use core_tenancy::with_tenant;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    interop::{
        auth::{require_scope, InteropClaims},
        error::FhirError,
    },
    AppState,
};

use integrations_interop::Scope;

/// Nombre maximum de créneaux renvoyés par `GET /v1/interop/fhir/Slot`
/// (recherche) — évite qu'un cabinet avec un agenda volumineux fasse
/// remonter des mégaoctets de JSON en un seul appel.
const MAX_SEARCH_RESULTS: i64 = 500;

/// Projection minimale d'une ligne `availability_slot` nécessaire au mapping
/// FHIR — séparée de la lecture DB pour pouvoir tester `slot_to_fhir` sans
/// base.
#[derive(Debug, Clone, PartialEq)]
struct SlotRow {
    id: Uuid,
    /// Toujours renseigné pour un créneau créé côté BO cabinet (`cabinet_id`
    /// et `practitioner_id` posés ensemble, `create_cabinet_slot`), mais la
    /// colonne reste nullable en base (créneaux marketplace hérités, lot
    /// 0009/0132) — traité en `Option` fail-closed plutôt que de supposer sa
    /// présence.
    practitioner_id: Option<Uuid>,
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
    status: String,
}

/// Mappe le statut interne `availability_slot.status` (CHECK
/// `'open'|'held'|'booked'|'blocked'`, migrations 0009/0075/0139) vers
/// l'enum FHIR `Slot.status` (`free|busy|busy-unavailable|busy-tentative|
/// entered-in-error`).
///
/// - `open`    → `free`             (réservable)
/// - `held`    → `busy-tentative`   (hold éphémère en cours, `hold_token`)
/// - `booked`  → `busy`             (RDV confirmé)
/// - `blocked` → `busy-unavailable` (bloqué manuellement côté BO, #3551)
///
/// Un statut inconnu (ne devrait pas arriver, contrainte CHECK en base)
/// retombe fail-closed sur `busy-unavailable` plutôt que `free` : mieux vaut
/// sous-annoncer la disponibilité qu'exposer par erreur un créneau qui ne
/// l'est pas.
fn map_slot_status(status: &str) -> &'static str {
    match status {
        "open" => "free",
        "held" => "busy-tentative",
        "booked" => "busy",
        "blocked" => "busy-unavailable",
        _ => "busy-unavailable",
    }
}

/// Construit la ressource FHIR `Slot` à partir d'une ligne `availability_slot`.
///
/// `schedule` n'est inclus que si `practitioner_id` est connu — en toute
/// rigueur FHIR `Slot.schedule` est à cardinalité `1..1`, mais on ne fabrique
/// pas de référence vers un praticien qu'on n'a pas (créneau marketplace
/// hérité sans `practitioner_id`) plutôt que de mentir sur la donnée.
fn slot_to_fhir(row: &SlotRow) -> Value {
    let mut resource = json!({
        "resourceType": "Slot",
        "id": row.id.to_string(),
        "status": map_slot_status(&row.status),
        "start": row.starts_at.to_rfc3339(),
        "end": row.ends_at.to_rfc3339(),
    });
    if let Some(practitioner_id) = row.practitioner_id {
        resource["schedule"] = json!({ "reference": format!("Schedule/{practitioner_id}") });
    }
    resource
}

/// Construit le `Bundle` FHIR `searchset` renvoyé par la recherche `Slot`.
fn slots_to_bundle(rows: &[SlotRow]) -> Value {
    let entries: Vec<Value> = rows
        .iter()
        .map(|row| json!({ "resource": slot_to_fhir(row) }))
        .collect();
    json!({
        "resourceType": "Bundle",
        "type": "searchset",
        "total": entries.len(),
        "entry": entries,
    })
}

/// Extrait les champs `SlotRow` d'une `sqlx::postgres::PgRow` générique
/// (requête construite via `sqlx::query`, pas `query_as!` — pas de Postgres
/// migré au schéma courant disponible pour préparer les macros, même
/// contrainte que le lot A1/`oauth.rs`).
fn row_to_slot(row: &sqlx::postgres::PgRow) -> Result<SlotRow, FhirError> {
    Ok(SlotRow {
        id: row.try_get("id").map_err(|_| FhirError::Internal)?,
        practitioner_id: row
            .try_get("practitioner_id")
            .map_err(|_| FhirError::Internal)?,
        starts_at: row.try_get("starts_at").map_err(|_| FhirError::Internal)?,
        ends_at: row.try_get("ends_at").map_err(|_| FhirError::Internal)?,
        status: row.try_get("status").map_err(|_| FhirError::Internal)?,
    })
}

/// `GET /v1/interop/fhir/Slot/:id` — un créneau par id interne.
///
/// 404 (jamais un 403/autre signal distinctif) si l'id est inconnu, supprimé
/// (`deleted_at`), ou appartient à un autre cabinet que celui du token — pas
/// de fuite d'existence cross-tenant.
pub async fn get_slot(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::SlotsRead)?;

    let cabinet_id = claims.cabinet_id;
    let row = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query(
            "SELECT id, practitioner_id, starts_at, ends_at, status \
             FROM availability_slot \
             WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await?;
        Ok(row)
    })
    .await
    .map_err(|_| FhirError::Internal)?;

    let row = row.ok_or(FhirError::NotFound)?;
    let slot = row_to_slot(&row)?;

    Ok(Json(slot_to_fhir(&slot)))
}

/// Paramètres de `GET /v1/interop/fhir/Slot` (recherche).
///
/// `from`/`to` sont des bornes ISO 8601 sur `starts_at` (`from` inclusif,
/// `to` exclusif) — voir le choix documenté en tête de fichier.
#[derive(Debug, Deserialize)]
pub struct SearchSlotsQuery {
    pub from: Option<String>,
    pub to: Option<String>,
}

/// `GET /v1/interop/fhir/Slot` — recherche de créneaux du cabinet du token,
/// bornée à `MAX_SEARCH_RESULTS` et triée par `starts_at`.
///
/// `from`/`to` malformés (non ISO 8601) → `400 invalid` (`OperationOutcome`),
/// plutôt que de les ignorer silencieusement.
pub async fn search_slots(
    State(state): State<AppState>,
    claims: InteropClaims,
    Query(params): Query<SearchSlotsQuery>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::SlotsRead)?;

    let from = parse_search_bound(params.from.as_deref(), "from")?;
    let to = parse_search_bound(params.to.as_deref(), "to")?;

    let cabinet_id = claims.cabinet_id;
    let rows = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let rows = sqlx::query(
            "SELECT id, practitioner_id, starts_at, ends_at, status \
             FROM availability_slot \
             WHERE cabinet_id = $1 \
               AND deleted_at IS NULL \
               AND ($2::timestamptz IS NULL OR starts_at >= $2) \
               AND ($3::timestamptz IS NULL OR starts_at < $3) \
             ORDER BY starts_at \
             LIMIT $4",
        )
        .bind(cabinet_id)
        .bind(from)
        .bind(to)
        .bind(MAX_SEARCH_RESULTS)
        .fetch_all(&mut *tx)
        .await?;
        Ok(rows)
    })
    .await
    .map_err(|_| FhirError::Internal)?;

    let slots = rows
        .iter()
        .map(row_to_slot)
        .collect::<Result<Vec<_>, FhirError>>()?;

    Ok(Json(slots_to_bundle(&slots)))
}

/// Parse une borne de recherche ISO 8601 optionnelle — `None`/absente reste
/// `None` (pas de borne), une chaîne présente mais invalide est un
/// `400 invalid` explicite (`param` identifie le paramètre en cause dans le
/// diagnostic).
fn parse_search_bound(raw: Option<&str>, param: &str) -> Result<Option<DateTime<Utc>>, FhirError> {
    match raw {
        None => Ok(None),
        Some(s) if s.trim().is_empty() => Ok(None),
        Some(s) => s.parse::<DateTime<Utc>>().map(Some).map_err(|_| {
            FhirError::InvalidParameter(format!("paramètre `{param}` invalide, attendu ISO 8601"))
        }),
    }
}

/// `GET /v1/interop/fhir/Schedule/:id` — ressource `Schedule` synthétique
/// représentant l'agenda d'un praticien (`id` = `practitioner.id`).
///
/// Ne modélise que le strict nécessaire à `Slot.schedule` : le contenu réel
/// vit dans `Slot`. `Practitioner`/`Organization` restent hors périmètre
/// (autres lots) — `actor` référence `Practitioner/:id` sans ressource
/// `Practitioner` réellement exposée pour l'instant.
pub async fn get_schedule(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(practitioner_id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::SlotsRead)?;

    let cabinet_id = claims.cabinet_id;
    let found = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query("SELECT id FROM practitioner WHERE id = $1 AND cabinet_id = $2")
            .bind(practitioner_id)
            .bind(cabinet_id)
            .fetch_optional(&mut *tx)
            .await?;
        Ok(row.is_some())
    })
    .await
    .map_err(|_| FhirError::Internal)?;

    if !found {
        return Err(FhirError::NotFound);
    }

    Ok(Json(json!({
        "resourceType": "Schedule",
        "id": practitioner_id.to_string(),
        "actor": [{ "reference": format!("Practitioner/{practitioner_id}") }],
    })))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn slot_row(status: &str, practitioner_id: Option<Uuid>) -> SlotRow {
        SlotRow {
            id: Uuid::new_v4(),
            practitioner_id,
            starts_at: Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap(),
            ends_at: Utc.with_ymd_and_hms(2026, 7, 20, 9, 30, 0).unwrap(),
            status: status.to_string(),
        }
    }

    #[test]
    fn map_slot_status_open_is_free() {
        assert_eq!(map_slot_status("open"), "free");
    }

    #[test]
    fn map_slot_status_booked_is_busy() {
        assert_eq!(map_slot_status("booked"), "busy");
    }

    #[test]
    fn map_slot_status_held_is_busy_tentative() {
        assert_eq!(map_slot_status("held"), "busy-tentative");
    }

    #[test]
    fn map_slot_status_blocked_is_busy_unavailable() {
        assert_eq!(map_slot_status("blocked"), "busy-unavailable");
    }

    #[test]
    fn map_slot_status_unknown_fails_closed_to_busy_unavailable() {
        assert_eq!(map_slot_status("something-new"), "busy-unavailable");
    }

    #[test]
    fn slot_to_fhir_includes_schedule_reference_when_practitioner_known() {
        let practitioner_id = Uuid::new_v4();
        let row = slot_row("open", Some(practitioner_id));
        let resource = slot_to_fhir(&row);

        assert_eq!(resource["resourceType"], "Slot");
        assert_eq!(resource["id"], row.id.to_string());
        assert_eq!(resource["status"], "free");
        assert_eq!(resource["start"], row.starts_at.to_rfc3339());
        assert_eq!(resource["end"], row.ends_at.to_rfc3339());
        assert_eq!(
            resource["schedule"]["reference"],
            format!("Schedule/{practitioner_id}")
        );
    }

    #[test]
    fn slot_to_fhir_omits_schedule_reference_when_practitioner_unknown() {
        let row = slot_row("booked", None);
        let resource = slot_to_fhir(&row);

        assert_eq!(resource["status"], "busy");
        assert!(resource.get("schedule").is_none());
    }

    #[test]
    fn slots_to_bundle_wraps_entries_as_searchset() {
        let rows = vec![
            slot_row("open", Some(Uuid::new_v4())),
            slot_row("held", None),
        ];
        let bundle = slots_to_bundle(&rows);

        assert_eq!(bundle["resourceType"], "Bundle");
        assert_eq!(bundle["type"], "searchset");
        assert_eq!(bundle["total"], 2);
        assert_eq!(bundle["entry"].as_array().unwrap().len(), 2);
        assert_eq!(bundle["entry"][0]["resource"]["status"], "free");
        assert_eq!(bundle["entry"][1]["resource"]["status"], "busy-tentative");
    }

    #[test]
    fn slots_to_bundle_is_empty_searchset_when_no_rows() {
        let bundle = slots_to_bundle(&[]);
        assert_eq!(bundle["total"], 0);
        assert_eq!(bundle["entry"].as_array().unwrap().len(), 0);
    }

    #[test]
    fn parse_search_bound_accepts_none() {
        assert_eq!(parse_search_bound(None, "from").unwrap(), None);
    }

    #[test]
    fn parse_search_bound_accepts_empty_string_as_none() {
        assert_eq!(parse_search_bound(Some("  "), "from").unwrap(), None);
    }

    #[test]
    fn parse_search_bound_parses_valid_rfc3339() {
        let parsed = parse_search_bound(Some("2026-07-20T09:00:00Z"), "from").unwrap();
        assert_eq!(
            parsed,
            Some(Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap())
        );
    }

    #[test]
    fn parse_search_bound_rejects_malformed_date() {
        let err = parse_search_bound(Some("not-a-date"), "from").unwrap_err();
        assert!(matches!(err, FhirError::InvalidParameter(msg) if msg.contains("from")));
    }
}
