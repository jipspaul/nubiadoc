//! `/v1/interop/fhir/Patient` — recherche/lecture FHIR des patients (lot A4).
//!
//! Dépend du socle A1 (scopes/JWT, `integrations-interop`) ET de
//! l'implémentation réelle de `core-crypto` (déchiffrement de l'INS, cf.
//! NUB-T3) — le scaffold `CryptoError::NotImplemented` d'origine bloquait ce
//! lot (#3915).
//!
//! ## RLS — ATTENTION `patient_account`
//!
//! `patient_account` est une table **plateforme** (pas de RLS `cabinet_id`,
//! cf. `db/migrations/0009_marketplace.sql`) : elle porte les données civiles
//! partagées entre cabinets (INS, identité) pour un même patient multi-cabinet.
//! Un client interop est scopé à UN cabinet — il ne doit **jamais** lire
//! `patient_account` directement (aucun filtre RLS ne l'en empêcherait). Le
//! chemin obligatoire est donc : lire `patient` (RLS `cabinet_id`, garantit le
//! cloisonnement tenant), puis déréférencer `patient.patient_account_id` pour
//! aller chercher l'INS chiffré dans `patient_account` — jamais l'inverse.
//!
//! ## Recherche
//!
//! - Par identifiant INS (`identifier=urn:oid:1.2.250.1.213.1.4.8|<ins>`) :
//!   l'INS est chiffré (`patient_account.ins_ciphertext`/`ins_key_ref`), donc
//!   invérifiable par une clause SQL — on déchiffre chaque candidat du cabinet
//!   (ceux qui ont un `patient_account_id` avec un INS renseigné) et on compare
//!   en clair. Coût O(n) sur la patientèle du cabinet, acceptable au volume
//!   d'un cabinet (pas un index cross-cabinet).
//! - Repli nom + naissance (`given`/`family`/`birthdate`), normalisés (casse,
//!   accents, espaces) pour tolérer les variantes de saisie.
//!
//! Erreurs rendues en `OperationOutcome` FHIR (cf. `interop::error::FhirError`),
//! comme les lots siblings A2/A3/A6.

use axum::{
    extract::{Path, Query, State},
    Json,
};
use core_crypto::{decrypt_column, KeyManager, LocalKeyManager};
use core_tenancy::with_tenant;
use serde::Deserialize;
use serde_json::{json, Value};
use sqlx::Row;
use uuid::Uuid;

use integrations_interop::Scope;

use crate::{
    interop::{
        auth::{require_scope, InteropClaims},
        error::FhirError,
    },
    AppState,
};

/// OID FHIR/ANS de l'identifiant national de santé.
pub const INS_SYSTEM: &str = "urn:oid:1.2.250.1.213.1.4.8";

/// Contexte d'enveloppement des colonnes `patient_account.*` — cf. doc de
/// `core_crypto::encrypt_column` : `"platform"` pour une donnée non
/// cabinet-scopée (`patient_account` est une table plateforme, pas tenant).
const PLATFORM_KEY_CONTEXT: &str = "platform";

/// Construit le [`KeyManager`] local (POC/dev) depuis `KMS_MASTER_KEY`
/// (32 octets, base64) — même convention que `infra/poc/compose.yml`. Ce
/// module ne construit PAS de `ScalewayKeyManager` : le choix du driver KMS
/// (local vs Scaleway) reste un câblage applicatif hors du périmètre de ce
/// lot (cf. doc de module `core_crypto`), le driver local suffit à débloquer
/// la lecture/recherche patient elle-même.
///
/// Échoue en [`FhirError::Internal`] (jamais de fallback en clair) si
/// `KMS_MASTER_KEY` est absente/mal formée.
fn key_manager_from_env() -> Result<LocalKeyManager, FhirError> {
    use base64::{engine::general_purpose::STANDARD, Engine};

    let raw = std::env::var("KMS_MASTER_KEY").map_err(|_| FhirError::Internal)?;
    let decoded = STANDARD
        .decode(raw.trim())
        .map_err(|_| FhirError::Internal)?;
    let key: [u8; 32] = decoded.try_into().map_err(|_| FhirError::Internal)?;
    Ok(LocalKeyManager::new(
        key,
        std::env::var("KMS_KEY_VERSION").unwrap_or_else(|_| "v1".to_string()),
    ))
}

/// Normalise un nom (casse, accents, espaces superflus) pour une comparaison
/// tolérante — même finalité que le "repli nom+naissance normalisé" demandé
/// par l'issue. Fold ASCII simple (suffisant pour les diacritiques latins
/// courants en France), pas une dépendance ICU complète.
fn normalize_name(raw: &str) -> String {
    raw.trim()
        .chars()
        .filter(|c| !c.is_whitespace())
        .flat_map(|c| c.to_lowercase())
        .map(|c| match c {
            'à' | 'â' | 'ä' | 'á' => 'a',
            'ç' => 'c',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' | 'í' | 'ì' => 'i',
            'ô' | 'ö' | 'ó' | 'ò' => 'o',
            'ù' | 'û' | 'ü' | 'ú' => 'u',
            other => other,
        })
        .collect()
}

/// Ligne DB minimale d'un `patient`, jointe (optionnellement) à son
/// `patient_account` — le SELECT `patient_account` se fait via une requête
/// séparée après déréférencement de `patient_account_id` (cf. doc de module),
/// jamais un JOIN direct sur `patient_account` sous le seul contexte tenant.
struct PatientRow {
    id: Uuid,
    first_name: String,
    last_name: String,
    birth_date: Option<chrono::NaiveDate>,
    contact: Value,
    patient_account_id: Option<Uuid>,
}

/// Charge, sous le contexte tenant déjà positionné par [`with_tenant`], l'INS
/// déchiffré d'un `patient` via son `patient_account_id` — requête séparée,
/// explicite, sur `patient_account` (table plateforme SANS RLS) : c'est la
/// SEULE façon licite d'atteindre cette table depuis un client externe (cf.
/// doc de module). Retourne `None` si le patient n'a pas de compte lié, ou si
/// l'INS n'est pas renseigné.
async fn load_decrypted_ins(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    key_manager: &dyn KeyManager,
    patient_account_id: Uuid,
) -> Result<Option<String>, FhirError> {
    let row = sqlx::query(
        "SELECT ins_ciphertext, ins_key_ref FROM patient_account WHERE id = $1 AND deleted_at IS NULL",
    )
    .bind(patient_account_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| FhirError::Internal)?;

    let Some(row) = row else {
        return Ok(None);
    };

    let ciphertext: Option<Vec<u8>> = row
        .try_get("ins_ciphertext")
        .map_err(|_| FhirError::Internal)?;
    let key_ref: Option<String> = row
        .try_get("ins_key_ref")
        .map_err(|_| FhirError::Internal)?;

    let (Some(ciphertext), Some(key_ref)) = (ciphertext, key_ref) else {
        return Ok(None);
    };

    let plaintext = decrypt_column(&ciphertext, key_manager, PLATFORM_KEY_CONTEXT, &key_ref)
        .await
        .map_err(|_| FhirError::Internal)?;

    String::from_utf8(plaintext)
        .map(Some)
        .map_err(|_| FhirError::Internal)
}

/// Mappe une ligne patient (+ INS déchiffré éventuel) vers un `Patient` FHIR R4.
fn patient_to_fhir(row: &PatientRow, ins: Option<&str>) -> Value {
    let mut resource = json!({
        "resourceType": "Patient",
        "id": row.id.to_string(),
        "name": [{
            "family": row.last_name,
            "given": [row.first_name],
            "text": format!("{} {}", row.first_name, row.last_name),
        }],
    });

    if let Some(birth_date) = row.birth_date {
        resource["birthDate"] = json!(birth_date.format("%Y-%m-%d").to_string());
    }

    if let Some(ins) = ins {
        resource["identifier"] = json!([{
            "system": INS_SYSTEM,
            "value": ins,
        }]);
    }

    if let Some(email) = row.contact.get("email").and_then(|v| v.as_str()) {
        resource["telecom"] = json!([{ "system": "email", "value": email }]);
    }

    resource
}

/// `GET /v1/interop/fhir/Patient/:id` — lecture d'un patient par UUID interne,
/// scopé au cabinet du token (`patient.cabinet_id`, RLS + filtre explicite).
pub async fn get_patient(
    State(state): State<AppState>,
    claims: InteropClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::PatientsRead)?;
    let key_manager = key_manager_from_env()?;
    let cabinet_id = claims.cabinet_id;

    let (row, ins) = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let row = sqlx::query(
            "SELECT id, first_name, last_name, birth_date, contact, patient_account_id \
             FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
        )
        .bind(id)
        .bind(cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(core_tenancy::TenancyError::Db)?;

        let Some(row) = row else {
            return Ok((None, None));
        };

        let patient = PatientRow {
            id: row.try_get("id").map_err(core_tenancy::TenancyError::Db)?,
            first_name: row
                .try_get("first_name")
                .map_err(core_tenancy::TenancyError::Db)?,
            last_name: row
                .try_get("last_name")
                .map_err(core_tenancy::TenancyError::Db)?,
            birth_date: row
                .try_get("birth_date")
                .map_err(core_tenancy::TenancyError::Db)?,
            contact: row
                .try_get("contact")
                .map_err(core_tenancy::TenancyError::Db)?,
            patient_account_id: row
                .try_get("patient_account_id")
                .map_err(core_tenancy::TenancyError::Db)?,
        };

        let ins = match patient.patient_account_id {
            Some(account_id) => load_decrypted_ins(&mut tx, &key_manager, account_id)
                .await
                .map_err(|_| core_tenancy::TenancyError::Db(sqlx::Error::RowNotFound))?,
            None => None,
        };

        Ok((Some(patient), ins))
    })
    .await
    .map_err(|_| FhirError::Internal)?;

    let row = row.ok_or(FhirError::NotFound)?;
    Ok(Json(patient_to_fhir(&row, ins.as_deref())))
}

/// Paramètres de recherche `GET /v1/interop/fhir/Patient`.
///
/// - `identifier` : `<system>|<value>` — seul `INS_SYSTEM` est supporté ;
///   toute autre valeur de `system` donne un `Bundle` vide (pas une erreur —
///   sémantique FHIR search standard, cf. `directory::search_practitioners`).
/// - `given`/`family`/`birthdate` : repli nom + naissance, tous requis
///   ensemble (une recherche nom seul sans naissance serait trop permissive
///   sur de l'identité patient — `400` si l'un des trois manque quand
///   `identifier` est absent).
#[derive(Debug, Deserialize)]
pub struct PatientSearchQuery {
    pub identifier: Option<String>,
    pub given: Option<String>,
    pub family: Option<String>,
    pub birthdate: Option<String>,
}

enum SearchStrategy {
    ByIns(String),
    ByNameAndBirth {
        given: String,
        family: String,
        birth_date: chrono::NaiveDate,
    },
}

fn parse_search_strategy(query: &PatientSearchQuery) -> Result<SearchStrategy, FhirError> {
    if let Some(identifier) = &query.identifier {
        let (system, value) = identifier.split_once('|').ok_or_else(|| {
            FhirError::InvalidParameter(
                "identifier doit être de la forme <system>|<value>".to_string(),
            )
        })?;
        if system != INS_SYSTEM {
            // Système non supporté : Bundle vide, pas une erreur (cf. doc struct).
            return Ok(SearchStrategy::ByIns(String::new()));
        }
        return Ok(SearchStrategy::ByIns(value.to_string()));
    }

    match (&query.given, &query.family, &query.birthdate) {
        (Some(given), Some(family), Some(birthdate)) => {
            let birth_date = birthdate.parse::<chrono::NaiveDate>().map_err(|_| {
                FhirError::InvalidParameter("birthdate invalide (YYYY-MM-DD attendu)".to_string())
            })?;
            Ok(SearchStrategy::ByNameAndBirth {
                given: given.clone(),
                family: family.clone(),
                birth_date,
            })
        }
        _ => Err(FhirError::InvalidParameter(
            "identifier=, ou given=+family=+birthdate= ensemble, requis".to_string(),
        )),
    }
}

/// `GET /v1/interop/fhir/Patient` — recherche par INS ou par repli
/// nom+naissance, scopée au cabinet du token.
pub async fn search_patients(
    State(state): State<AppState>,
    claims: InteropClaims,
    Query(query): Query<PatientSearchQuery>,
) -> Result<Json<Value>, FhirError> {
    require_scope(&claims, Scope::PatientsRead)?;
    let strategy = parse_search_strategy(&query)?;
    let cabinet_id = claims.cabinet_id;

    // `identifier` avec un système non-INS → Bundle vide immédiat, pas de
    // requête DB (cf. `parse_search_strategy`).
    if let SearchStrategy::ByIns(ref ins) = strategy {
        if ins.is_empty()
            && query
                .identifier
                .as_deref()
                .is_some_and(|i| !i.contains(INS_SYSTEM))
        {
            return Ok(Json(bundle_searchset(vec![])));
        }
    }

    let key_manager = key_manager_from_env()?;

    let resources = with_tenant(&state.db, cabinet_id, move |mut tx| async move {
        let candidates = sqlx::query(
            "SELECT id, first_name, last_name, birth_date, contact, patient_account_id \
             FROM patient WHERE cabinet_id = $1 AND deleted_at IS NULL \
             ORDER BY id LIMIT 200",
        )
        .bind(cabinet_id)
        .fetch_all(&mut *tx)
        .await
        .map_err(core_tenancy::TenancyError::Db)?;

        let mut out = Vec::new();
        for row in candidates {
            let patient = PatientRow {
                id: row.try_get("id").map_err(core_tenancy::TenancyError::Db)?,
                first_name: row
                    .try_get("first_name")
                    .map_err(core_tenancy::TenancyError::Db)?,
                last_name: row
                    .try_get("last_name")
                    .map_err(core_tenancy::TenancyError::Db)?,
                birth_date: row
                    .try_get("birth_date")
                    .map_err(core_tenancy::TenancyError::Db)?,
                contact: row
                    .try_get("contact")
                    .map_err(core_tenancy::TenancyError::Db)?,
                patient_account_id: row
                    .try_get("patient_account_id")
                    .map_err(core_tenancy::TenancyError::Db)?,
            };

            match &strategy {
                SearchStrategy::ByIns(target_ins) => {
                    if target_ins.is_empty() {
                        continue;
                    }
                    let Some(account_id) = patient.patient_account_id else {
                        continue;
                    };
                    let ins = load_decrypted_ins(&mut tx, &key_manager, account_id)
                        .await
                        .map_err(|_| core_tenancy::TenancyError::Db(sqlx::Error::RowNotFound))?;
                    if ins.as_deref() == Some(target_ins.as_str()) {
                        out.push(patient_to_fhir(&patient, ins.as_deref()));
                    }
                }
                SearchStrategy::ByNameAndBirth {
                    given,
                    family,
                    birth_date,
                } => {
                    let matches_name = normalize_name(&patient.first_name) == normalize_name(given)
                        && normalize_name(&patient.last_name) == normalize_name(family);
                    let matches_birth = patient.birth_date == Some(*birth_date);
                    if matches_name && matches_birth {
                        out.push(patient_to_fhir(&patient, None));
                    }
                }
            }
        }

        Ok(out)
    })
    .await
    .map_err(|_| FhirError::Internal)?;

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_name_folds_accents_case_and_spaces() {
        assert_eq!(normalize_name("Éric   Dupont"), "ericdupont");
        assert_eq!(normalize_name("eric dupont"), "ericdupont");
        assert_eq!(normalize_name(" ÉRIC DUPONT "), "ericdupont");
    }

    #[test]
    fn parse_search_strategy_requires_identifier_or_full_name_birth_triplet() {
        let empty = PatientSearchQuery {
            identifier: None,
            given: None,
            family: None,
            birthdate: None,
        };
        assert!(matches!(
            parse_search_strategy(&empty),
            Err(FhirError::InvalidParameter(_))
        ));

        let partial = PatientSearchQuery {
            identifier: None,
            given: Some("Eric".to_string()),
            family: None,
            birthdate: Some("1990-01-01".to_string()),
        };
        assert!(matches!(
            parse_search_strategy(&partial),
            Err(FhirError::InvalidParameter(_))
        ));
    }

    #[test]
    fn parse_search_strategy_accepts_ins_identifier() {
        let query = PatientSearchQuery {
            identifier: Some(format!("{INS_SYSTEM}|1234567890123")),
            given: None,
            family: None,
            birthdate: None,
        };
        match parse_search_strategy(&query).unwrap() {
            SearchStrategy::ByIns(value) => assert_eq!(value, "1234567890123"),
            _ => panic!("expected ByIns"),
        }
    }

    #[test]
    fn parse_search_strategy_rejects_malformed_identifier() {
        let query = PatientSearchQuery {
            identifier: Some("no-pipe-here".to_string()),
            given: None,
            family: None,
            birthdate: None,
        };
        assert!(matches!(
            parse_search_strategy(&query),
            Err(FhirError::InvalidParameter(_))
        ));
    }

    #[test]
    fn parse_search_strategy_unsupported_system_yields_empty_ins() {
        let query = PatientSearchQuery {
            identifier: Some("urn:oid:9.9.9.9|whatever".to_string()),
            given: None,
            family: None,
            birthdate: None,
        };
        match parse_search_strategy(&query).unwrap() {
            SearchStrategy::ByIns(value) => assert!(value.is_empty()),
            _ => panic!("expected ByIns"),
        }
    }

    #[test]
    fn parse_search_strategy_accepts_full_name_birth_triplet() {
        let query = PatientSearchQuery {
            identifier: None,
            given: Some("Eric".to_string()),
            family: Some("Dupont".to_string()),
            birthdate: Some("1990-05-12".to_string()),
        };
        match parse_search_strategy(&query).unwrap() {
            SearchStrategy::ByNameAndBirth {
                given,
                family,
                birth_date,
            } => {
                assert_eq!(given, "Eric");
                assert_eq!(family, "Dupont");
                assert_eq!(
                    birth_date,
                    chrono::NaiveDate::from_ymd_opt(1990, 5, 12).unwrap()
                );
            }
            _ => panic!("expected ByNameAndBirth"),
        }
    }

    #[test]
    fn parse_search_strategy_rejects_invalid_birthdate() {
        let query = PatientSearchQuery {
            identifier: None,
            given: Some("Eric".to_string()),
            family: Some("Dupont".to_string()),
            birthdate: Some("not-a-date".to_string()),
        };
        assert!(matches!(
            parse_search_strategy(&query),
            Err(FhirError::InvalidParameter(_))
        ));
    }

    #[test]
    fn bundle_searchset_wraps_resources_with_total() {
        let bundle = bundle_searchset(vec![json!({"resourceType": "Patient", "id": "1"})]);
        assert_eq!(bundle["resourceType"], "Bundle");
        assert_eq!(bundle["total"], 1);
        assert_eq!(bundle["entry"][0]["resource"]["id"], "1");
    }
}
