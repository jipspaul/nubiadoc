//! Annuaire FHIR en lecture seule (lot A2) : `Practitioner`/`Organization`/
//! `Location`, tous scopés au `cabinet_id` du token partenaire ([`InteropClaims`]).
//!
//! Toutes les routes exigent `Scope::DirectoryRead` (`require_scope`) et lisent
//! via [`core_tenancy::with_tenant`] — premier appelant réel de ce helper dans
//! `api/src` (le reste du code pré-existant pose le GUC `app.current_cabinet_id`
//! à la main via `begin()`/`set_config`/`commit()`, cf. `scheduling.rs`).
//!
//! Le filtre tenant est **explicite dans chaque requête**, jamais laissé à la
//! seule RLS : en particulier `establishment` (mappé vers `Location`) n'a
//! *aucune* policy RLS (cf. commentaire `db/migrations/0011_rls_policies.sql`,
//! "Entités plateforme SANS cabinet_id : pas de RLS cabinet") — sans jointure
//! explicite `provider.cabinet_id = $cabinet_id`, n'importe quel établissement
//! de n'importe quel cabinet serait lisible par un rôle `nubia_app`.
//!
//! Erreurs rendues en `OperationOutcome` (FHIR), pas RFC 6749 — cf.
//! [`crate::interop::error::FhirError`]. Lecture seule : aucune écriture sur
//! `practitioner`/`cabinet`/`establishment` dans ce lot.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use core_tenancy::with_tenant;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::{postgres::PgRow, Row};
use uuid::Uuid;

use integrations_interop::Scope;

use crate::{
    interop::{
        auth::{require_scope, InteropClaims},
        error::FhirError,
    },
    AppState,
};

// ── Practitioner ─────────────────────────────────────────────────────────────

/// Colonnes lues pour mapper un `Practitioner` FHIR — `practitioner` (tenant,
/// RLS `cabinet_id = GUC`) jointe à `app_user` (identité civile) et, en
/// `LEFT JOIN`, à `provider` (fiche marketplace publique, optionnelle : un
/// praticien peut ne pas avoir de profil public). `$1` = `cabinet_id`.
const PRACTITIONER_SELECT_BY_ID: &str =
    "SELECT p.id, p.rpps, u.first_name, u.last_name, pr.display_name \
     FROM practitioner p \
     JOIN app_user u ON u.id = p.user_id \
     LEFT JOIN provider pr ON pr.practitioner_id = p.id AND pr.cabinet_id = p.cabinet_id \
     WHERE p.cabinet_id = $1 AND p.id = $2";

/// Même jointure que [`PRACTITIONER_SELECT_BY_ID`], sans le filtre `_id` —
/// liste des praticiens du cabinet.
const PRACTITIONER_SELECT_ALL: &str =
    "SELECT p.id, p.rpps, u.first_name, u.last_name, pr.display_name \
     FROM practitioner p \
     JOIN app_user u ON u.id = p.user_id \
     LEFT JOIN provider pr ON pr.practitioner_id = p.id AND pr.cabinet_id = p.cabinet_id \
     WHERE p.cabinet_id = $1 \
     ORDER BY p.id";

struct PractitionerRow {
    id: Uuid,
    rpps: Option<String>,
    first_name: Option<String>,
    last_name: Option<String>,
    display_name: Option<String>,
}

fn row_to_practitioner(row: &PgRow) -> Result<PractitionerRow, FhirError> {
    Ok(PractitionerRow {
        id: row.try_get("id").map_err(|_| FhirError::Internal)?,
        rpps: row.try_get("rpps").map_err(|_| FhirError::Internal)?,
        first_name: row.try_get("first_name").map_err(|_| FhirError::Internal)?,
        last_name: row.try_get("last_name").map_err(|_| FhirError::Internal)?,
        display_name: row
            .try_get("display_name")
            .map_err(|_| FhirError::Internal)?,
    })
}

/// Mappe une ligne DB vers un `Practitioner` FHIR R4 minimal.
///
/// `name` (`HumanName`) : construit depuis `app_user.first_name`/`last_name`
/// si renseignés ; sinon repli sur `provider.display_name` (`text` seul,
/// pas de `family`/`given`). Si aucune des deux sources n'est disponible,
/// `name` est omis (reste un `Practitioner` valide sans identité affichable).
/// `identifier` RPPS (`urn:oid:1.2.250.1.71.4.2.1`) ajouté seulement si
/// `practitioner.rpps` est renseigné.
fn practitioner_to_fhir(row: &PractitionerRow) -> Value {
    let mut resource = json!({
        "resourceType": "Practitioner",
        "id": row.id.to_string(),
    });

    if row.first_name.is_some() || row.last_name.is_some() {
        let mut name = json!({});
        if let Some(family) = &row.last_name {
            name["family"] = json!(family);
        }
        if let Some(given) = &row.first_name {
            name["given"] = json!([given]);
        }
        let text = [row.first_name.as_deref(), row.last_name.as_deref()]
            .into_iter()
            .flatten()
            .collect::<Vec<_>>()
            .join(" ");
        if !text.is_empty() {
            name["text"] = json!(text);
        }
        resource["name"] = json!([name]);
    } else if let Some(display_name) = &row.display_name {
        resource["name"] = json!([{ "text": display_name }]);
    }

    if let Some(rpps) = &row.rpps {
        resource["identifier"] = json!([{
            "system": "urn:oid:1.2.250.1.71.4.2.1",
            "value": rpps,
        }]);
    }

    resource
}

/// `GET /v1/interop/fhir/Practitioner/:id` — un praticien du cabinet du token.
///
/// `:id` d'un praticien d'un autre cabinet (même existant en base) → `404` :
/// le filtre `p.cabinet_id = $2` est explicite dans la requête, pas seulement
/// délégué à la RLS.
pub async fn get_practitioner(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::DirectoryRead)?;
    let cabinet_id = claims.cabinet_id;

    let row = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query(PRACTITIONER_SELECT_BY_ID)
            .bind(cabinet_id)
            .bind(id)
            .fetch_optional(&mut *tx)
            .await?;
        Ok(row)
    })
    .await
    .map_err(|_| FhirError::Internal)?
    .ok_or(FhirError::NotFound)?;

    let practitioner = row_to_practitioner(&row)?;
    Ok(Json(practitioner_to_fhir(&practitioner)))
}

/// Paramètres de recherche `GET /v1/interop/fhir/Practitioner`.
#[derive(Debug, Deserialize)]
pub struct PractitionerSearchParams {
    #[serde(rename = "_id")]
    pub id: Option<Uuid>,
}

/// `GET /v1/interop/fhir/Practitioner` — liste des praticiens du cabinet du
/// token (le cabinet fait implicitement office de portée de recherche : un
/// partenaire n'a jamais de recherche cross-cabinet). Filtre optionnel `_id`.
///
/// Toujours `200` avec un `Bundle` (même vide) — un `_id` qui ne correspond à
/// rien (absent, ou d'un autre cabinet) donne un `Bundle` vide, pas un `404`
/// (sémantique FHIR search standard).
pub async fn search_practitioners(
    State(state): State<AppState>,
    claims: InteropClaims,
    Query(params): Query<PractitionerSearchParams>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::DirectoryRead)?;
    let cabinet_id = claims.cabinet_id;
    let filter_id = params.id;

    let rows = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let rows = match filter_id {
            Some(id) => {
                sqlx::query(PRACTITIONER_SELECT_BY_ID)
                    .bind(cabinet_id)
                    .bind(id)
                    .fetch_all(&mut *tx)
                    .await?
            }
            None => {
                sqlx::query(PRACTITIONER_SELECT_ALL)
                    .bind(cabinet_id)
                    .fetch_all(&mut *tx)
                    .await?
            }
        };
        Ok(rows)
    })
    .await
    .map_err(|_| FhirError::Internal)?;

    let resources = rows
        .iter()
        .map(row_to_practitioner)
        .collect::<Result<Vec<_>, FhirError>>()?
        .iter()
        .map(practitioner_to_fhir)
        .collect();

    Ok(Json(bundle_searchset(resources)))
}

fn bundle_searchset(resources: Vec<Value>) -> Value {
    json!({
        "resourceType": "Bundle",
        "type": "searchset",
        "total": resources.len(),
        "entry": resources
            .into_iter()
            .map(|resource| json!({ "resource": resource }))
            .collect::<Vec<_>>(),
    })
}

// ── Organization ─────────────────────────────────────────────────────────────

/// `GET /v1/interop/fhir/Organization/:id` — le cabinet propriétaire du token.
///
/// Un partenaire ne voit jamais que son propre cabinet : `:id != cabinet_id`
/// du token → `404`, même si la ligne existe en base pour un autre cabinet —
/// vérifié explicitement *avant* la requête (pas seulement via la RLS
/// `tenant_isolation` sur `cabinet`, qui filtre déjà sur `id = GUC` mais dont
/// on ne veut pas dépendre seule pour ce choix de contrat API).
pub async fn get_organization(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::DirectoryRead)?;

    if id != claims.cabinet_id {
        return Err(FhirError::NotFound);
    }
    let cabinet_id = claims.cabinet_id;

    let row = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query(
            "SELECT id, raison_sociale FROM cabinet WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(id)
        .fetch_optional(&mut *tx)
        .await?;
        Ok(row)
    })
    .await
    .map_err(|_| FhirError::Internal)?
    .ok_or(FhirError::NotFound)?;

    let org_id: Uuid = row.try_get("id").map_err(|_| FhirError::Internal)?;
    let raison_sociale: String = row
        .try_get("raison_sociale")
        .map_err(|_| FhirError::Internal)?;

    Ok(Json(json!({
        "resourceType": "Organization",
        "id": org_id.to_string(),
        "name": raison_sociale,
    })))
}

// ── Location ─────────────────────────────────────────────────────────────────

/// Formate `establishment.address` (jsonb `{"rue":...,"cp":...,"ville":...}`,
/// même forme que `appointments::format_establishment_address`) en `Address`
/// FHIR minimal. `None`/objet vide si aucun des trois champs n'est renseigné.
fn location_address(address: &Value) -> Option<Value> {
    let line = address.get("rue").and_then(|v| v.as_str());
    let postal_code = address.get("cp").and_then(|v| v.as_str());
    let city = address.get("ville").and_then(|v| v.as_str());

    if line.is_none() && postal_code.is_none() && city.is_none() {
        return None;
    }

    let mut addr = json!({});
    if let Some(l) = line {
        addr["line"] = json!([l]);
    }
    if let Some(pc) = postal_code {
        addr["postalCode"] = json!(pc);
    }
    if let Some(c) = city {
        addr["city"] = json!(c);
    }
    Some(addr)
}

fn location_to_fhir(id: Uuid, name: &str, address: &Value) -> Value {
    let mut resource = json!({
        "resourceType": "Location",
        "id": id.to_string(),
        "name": name,
    });

    if let Some(addr) = location_address(address) {
        resource["address"] = addr;
    }

    resource
}

/// `GET /v1/interop/fhir/Location/:id` — un établissement (`establishment`) du
/// cabinet du token, via le lien marketplace `provider.establishment_id`.
///
/// `establishment` n'a **aucune** RLS (table plateforme, cf. commentaire de
/// module) : le `JOIN provider ON ... AND p.cabinet_id = $2` est donc la seule
/// garantie d'isolation tenant ici, pas un simple raffinement — sans lui,
/// n'importe quel `establishment_id` deviné serait lisible.
pub async fn get_location(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::DirectoryRead)?;
    let cabinet_id = claims.cabinet_id;

    let row = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query(
            "SELECT DISTINCT e.id, e.name, e.address \
             FROM establishment e \
             JOIN provider p ON p.establishment_id = e.id \
             WHERE e.id = $1 AND p.cabinet_id = $2",
        )
        .bind(id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await?;
        Ok(row)
    })
    .await
    .map_err(|_| FhirError::Internal)?
    .ok_or(FhirError::NotFound)?;

    let loc_id: Uuid = row.try_get("id").map_err(|_| FhirError::Internal)?;
    let name: String = row.try_get("name").map_err(|_| FhirError::Internal)?;
    let address: Value = row.try_get("address").map_err(|_| FhirError::Internal)?;

    Ok(Json(location_to_fhir(loc_id, &name, &address)))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn practitioner_row(
        rpps: Option<&str>,
        first_name: Option<&str>,
        last_name: Option<&str>,
        display_name: Option<&str>,
    ) -> PractitionerRow {
        PractitionerRow {
            id: Uuid::new_v4(),
            rpps: rpps.map(str::to_string),
            first_name: first_name.map(str::to_string),
            last_name: last_name.map(str::to_string),
            display_name: display_name.map(str::to_string),
        }
    }

    #[test]
    fn practitioner_to_fhir_uses_app_user_identity_when_present() {
        let row = practitioner_row(
            Some("10100000001"),
            Some("Alice"),
            Some("Martin"),
            Some("Dr Martin (marketplace)"),
        );
        let fhir = practitioner_to_fhir(&row);

        assert_eq!(fhir["resourceType"], "Practitioner");
        assert_eq!(fhir["id"], row.id.to_string());
        assert_eq!(fhir["name"][0]["family"], "Martin");
        assert_eq!(fhir["name"][0]["given"][0], "Alice");
        assert_eq!(fhir["name"][0]["text"], "Alice Martin");
        assert_eq!(
            fhir["identifier"][0]["system"],
            "urn:oid:1.2.250.1.71.4.2.1"
        );
        assert_eq!(fhir["identifier"][0]["value"], "10100000001");
    }

    #[test]
    fn practitioner_to_fhir_falls_back_to_provider_display_name() {
        let row = practitioner_row(None, None, None, Some("Dr Dupont"));
        let fhir = practitioner_to_fhir(&row);

        assert_eq!(fhir["name"][0]["text"], "Dr Dupont");
        assert!(fhir["name"][0].get("family").is_none());
        assert!(fhir.get("identifier").is_none());
    }

    #[test]
    fn practitioner_to_fhir_omits_name_when_no_identity_source() {
        let row = practitioner_row(None, None, None, None);
        let fhir = practitioner_to_fhir(&row);

        assert!(fhir.get("name").is_none());
        assert!(fhir.get("identifier").is_none());
        assert_eq!(fhir["resourceType"], "Practitioner");
    }

    #[test]
    fn practitioner_to_fhir_omits_identifier_when_no_rpps() {
        let row = practitioner_row(None, Some("Alice"), Some("Martin"), None);
        let fhir = practitioner_to_fhir(&row);

        assert!(fhir.get("identifier").is_none());
    }

    #[test]
    fn bundle_searchset_wraps_resources_with_total() {
        let bundle = bundle_searchset(vec![json!({"resourceType": "Practitioner", "id": "1"})]);

        assert_eq!(bundle["resourceType"], "Bundle");
        assert_eq!(bundle["type"], "searchset");
        assert_eq!(bundle["total"], 1);
        assert_eq!(bundle["entry"][0]["resource"]["id"], "1");
    }

    #[test]
    fn bundle_searchset_empty_is_a_valid_empty_bundle() {
        let bundle = bundle_searchset(vec![]);

        assert_eq!(bundle["total"], 0);
        assert_eq!(bundle["entry"], json!([]));
    }

    #[test]
    fn location_to_fhir_maps_address_fields() {
        let id = Uuid::new_v4();
        let address = json!({"rue": "12 rue de la Paix", "cp": "75002", "ville": "Paris"});
        let fhir = location_to_fhir(id, "Cabinet du Centre", &address);

        assert_eq!(fhir["resourceType"], "Location");
        assert_eq!(fhir["id"], id.to_string());
        assert_eq!(fhir["name"], "Cabinet du Centre");
        assert_eq!(fhir["address"]["line"][0], "12 rue de la Paix");
        assert_eq!(fhir["address"]["postalCode"], "75002");
        assert_eq!(fhir["address"]["city"], "Paris");
    }

    #[test]
    fn location_to_fhir_omits_address_when_empty() {
        let id = Uuid::new_v4();
        let fhir = location_to_fhir(id, "Cabinet du Centre", &json!({}));

        assert!(fhir.get("address").is_none());
    }
}
