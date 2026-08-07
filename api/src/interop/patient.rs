//! Mapping ADT (création/mise à jour patient) → couche service `patient`
//! (lot B8, appelé par `hl7v2::dispatch::process_message` pour tout message
//! du groupe `ADT`).
//!
//! Bloqué jusqu'ici (cf. commentaire historique dans `dispatch.rs`) sur
//! `crates/core/crypto` : celui-ci dispose désormais d'une implémentation
//! réelle (chiffrement d'enveloppe KMS, `LocalKeyManager`/`ScalewayKeyManager`),
//! ce lot peut donc être livré.
//!
//! ## Portée
//!
//! - **`ADT^A28`** (nouveau patient) : crée une ligne `patient` pour ce
//!   cabinet si aucune ne correspond déjà à l'INS extrait.
//! - **`ADT^A31`/`ADT^A08`** (mise à jour) : met à jour les champs
//!   démographiques (`first_name`/`last_name`/`birth_date`) d'un patient déjà
//!   connu de ce cabinet ; ne crée rien si l'INS ne résout à aucun patient
//!   existant (contrairement à A28).
//!
//! ## INS (`PID-3`, autorité `INS-NIR`) — jamais en clair
//!
//! `PID-3` porte une liste d'identifiants répétés (convention CX HL7 v2) ;
//! on cherche la répétition dont le composant 4 (autorité d'affectation)
//! vaut `INS-NIR` (cf. brief), composant 1 = l'INS lui-même. L'INS est une
//! donnée d'identité de santé critique (RGPD/HDS) : il n'est **jamais** logué
//! en clair (`tracing::*!` ne reçoit jamais l'INS extrait), et n'est **jamais**
//! stocké en clair — il transite par [`core_crypto::encrypt_column`] avant
//! toute écriture en base (`patient.ins_ciphertext`/`ins_key_ref`), avec
//! `key_context = cabinet_id` (comme les autres colonnes `*_ciphertext`
//! cabinet-scopées, cf. `docs/05` §3).
//!
//! Le matching d'un patient existant par INS déchiffre puis compare — pas de
//! recherche en clair côté SQL (`ins_ciphertext` est un `bytea` opaque, un
//! nonce aléatoire par valeur garantit qu'on ne peut même pas comparer deux
//! ciphertexts pour détecter une égalité, cf. `core_crypto` doc de module).
//! Coût O(n) sur les patients du cabinet ayant un INS enregistré — acceptable
//! ici (volume par cabinet, pas de recherche cross-tenant), pas d'index en
//! clair sur l'INS envisageable sans un blind index dédié (hors scope B8).

use core_crypto::{decrypt_column, encrypt_column, KeyManager};
use core_tenancy::with_tenant;
use integrations_hl7v2::message::{Message, Segment};
use sqlx::PgPool;
use uuid::Uuid;

/// Erreur de traitement ADT — `Display` fournit le texte renvoyé en `MSA-3`
/// (ACK `AE`) par `dispatch::process_message`, jamais de détail brut (INS,
/// erreur SQL).
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum AdtError {
    #[error("segment {0} manquant")]
    MissingSegment(&'static str),
    #[error("champ {0} manquant ou invalide")]
    InvalidField(&'static str),
    #[error("PID-3 : aucune répétition avec l'autorité d'affectation INS-NIR")]
    MissingIns,
    #[error("mise à jour (A31/A08) reçue pour un INS inconnu de ce cabinet")]
    PatientNotFoundForUpdate,
    #[error("erreur interne")]
    Internal,
}

/// Point d'entrée appelé par `dispatch::process_message` pour tout message
/// du groupe `ADT`. `trigger` est le composant 2 de `MSH-9` (ex. `"A28"`).
///
/// `key_manager` : chiffrement d'enveloppe de l'INS (`key_context =
/// cabinet_id.to_string()`) — jamais de fallback en clair.
pub async fn handle(
    db: &PgPool,
    cabinet_id: Uuid,
    key_manager: &dyn KeyManager,
    message: &Message,
    trigger: &str,
) -> Result<(), AdtError> {
    match trigger {
        "A28" => handle_new_patient(db, cabinet_id, key_manager, message).await,
        "A31" | "A08" => handle_update_patient(db, cabinet_id, key_manager, message).await,
        _ => Err(AdtError::InvalidField(
            "MSH-9.2 (déclencheur ADT non supporté)",
        )),
    }
}

/// `ADT^A28` : crée le patient s'il n'existe pas déjà (par INS) dans ce
/// cabinet. Idempotent : un A28 rejoué pour le même INS ne duplique pas la
/// fiche (retourne `Ok(())` sans réinsérer).
async fn handle_new_patient(
    db: &PgPool,
    cabinet_id: Uuid,
    key_manager: &dyn KeyManager,
    message: &Message,
) -> Result<(), AdtError> {
    let ins = extract_ins(message)?;
    let (first_name, last_name) = extract_name(message)?;
    let birth_date = extract_birth_date(message)?;
    let key_context = cabinet_id.to_string();

    if find_patient_by_ins(db, cabinet_id, key_manager, &key_context, &ins)
        .await?
        .is_some()
    {
        // Doublon (rejeu MSH-10 différent portant le même INS, ou nouvel
        // envoi du même patient) : pas de deuxième fiche pour le même INS.
        return Ok(());
    }

    let encrypted = encrypt_column(ins.as_bytes(), key_manager, &key_context)
        .await
        .map_err(|_| AdtError::Internal)?;

    with_tenant(db, cabinet_id, move |mut tx| async move {
        sqlx::query(
            "INSERT INTO patient \
             (cabinet_id, ins_ciphertext, ins_key_ref, first_name, last_name, birth_date) \
             VALUES ($1, $2, $3, $4, $5, $6)",
        )
        .bind(cabinet_id)
        .bind(&encrypted.ciphertext)
        .bind(&encrypted.key_ref)
        .bind(&first_name)
        .bind(&last_name)
        .bind(birth_date)
        .execute(&mut *tx)
        .await?;

        // Zéro PII en métadonnées d'audit : ni l'INS, ni le nom.
        sqlx::query(
            "INSERT INTO audit_log (cabinet_id, actor_role, action, entity) \
             VALUES ($1, 'hl7v2_partner', 'hl7v2_adt_patient_created', 'patient')",
        )
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    })
    .await
    .map_err(|_| AdtError::Internal)
}

/// `ADT^A31`/`A08` : met à jour la démographie d'un patient déjà connu de ce
/// cabinet (résolu par INS). Ne crée jamais de fiche — contrairement à A28,
/// une mise à jour pour un INS inconnu est une erreur explicite (`AE`), pas
/// un stub silencieux.
async fn handle_update_patient(
    db: &PgPool,
    cabinet_id: Uuid,
    key_manager: &dyn KeyManager,
    message: &Message,
) -> Result<(), AdtError> {
    let ins = extract_ins(message)?;
    let (first_name, last_name) = extract_name(message)?;
    let birth_date = extract_birth_date(message)?;
    let key_context = cabinet_id.to_string();

    let patient_id = find_patient_by_ins(db, cabinet_id, key_manager, &key_context, &ins)
        .await?
        .ok_or(AdtError::PatientNotFoundForUpdate)?;

    with_tenant(db, cabinet_id, move |mut tx| async move {
        sqlx::query(
            "UPDATE patient SET first_name = $1, last_name = $2, birth_date = $3, \
             updated_at = now() WHERE id = $4 AND cabinet_id = $5",
        )
        .bind(&first_name)
        .bind(&last_name)
        .bind(birth_date)
        .bind(patient_id)
        .bind(cabinet_id)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            "INSERT INTO audit_log (cabinet_id, actor_role, action, entity, entity_id) \
             VALUES ($1, 'hl7v2_partner', 'hl7v2_adt_patient_updated', 'patient', $2)",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    })
    .await
    .map_err(|_| AdtError::Internal)
}

/// Cherche, parmi les patients de `cabinet_id` ayant un INS enregistré, celui
/// dont l'INS déchiffré correspond à `ins`. Jamais de comparaison en clair
/// côté SQL — le déchiffrement se fait en Rust, une ligne à la fois.
async fn find_patient_by_ins(
    db: &PgPool,
    cabinet_id: Uuid,
    key_manager: &dyn KeyManager,
    key_context: &str,
    ins: &str,
) -> Result<Option<Uuid>, AdtError> {
    let rows: Vec<(Uuid, Vec<u8>, String)> =
        with_tenant(db, cabinet_id, move |mut tx| async move {
            let rows = sqlx::query_as::<_, (Uuid, Vec<u8>, String)>(
                "SELECT id, ins_ciphertext, ins_key_ref FROM patient \
             WHERE cabinet_id = $1 AND ins_ciphertext IS NOT NULL AND deleted_at IS NULL",
            )
            .bind(cabinet_id)
            .fetch_all(&mut *tx)
            .await?;
            Ok(rows)
        })
        .await
        .map_err(|_| AdtError::Internal)?;

    for (id, ciphertext, key_ref) in rows {
        if let Ok(plaintext) = decrypt_column(&ciphertext, key_manager, key_context, &key_ref).await
        {
            if plaintext == ins.as_bytes() {
                return Ok(Some(id));
            }
        }
    }
    Ok(None)
}

/// `PID-3` : cherche la répétition dont le composant 4 (autorité
/// d'affectation) vaut `INS-NIR` (convention CX HL7 v2, cf. brief) et
/// renvoie son composant 1 (l'INS lui-même). Jamais loggé.
fn extract_ins(message: &Message) -> Result<String, AdtError> {
    let pid = message
        .segment("PID")
        .ok_or(AdtError::MissingSegment("PID"))?;
    find_ins_nir_identifier(pid).ok_or(AdtError::MissingIns)
}

fn find_ins_nir_identifier(segment: &Segment) -> Option<String> {
    let repetitions = segment.repetitions(3)?;
    for (idx, _) in repetitions.enumerate() {
        let rep_n = idx + 1;
        if segment.component_in_repetition(3, rep_n, 4) == Some("INS-NIR") {
            let raw = segment.component_in_repetition(3, rep_n, 1)?;
            if !raw.is_empty() {
                return Some(raw.to_string());
            }
        }
    }
    None
}

/// `PID-5` : composant 1 = nom, composant 2 = prénom (convention XPN HL7 v2).
fn extract_name(message: &Message) -> Result<(String, String), AdtError> {
    let pid = message
        .segment("PID")
        .ok_or(AdtError::MissingSegment("PID"))?;
    let last_name = pid
        .component(5, 1)
        .filter(|s| !s.is_empty())
        .ok_or(AdtError::InvalidField("PID-5.1"))?;
    let first_name = pid
        .component(5, 2)
        .filter(|s| !s.is_empty())
        .ok_or(AdtError::InvalidField("PID-5.2"))?;
    Ok((first_name.to_string(), last_name.to_string()))
}

/// `PID-7` : date de naissance au format HL7 v2 TS court `AAAAMMJJ`.
/// Optionnelle : absente ou vide → `None` (pas d'erreur, le brief ne
/// documente pas PID-7 comme obligatoire).
fn extract_birth_date(message: &Message) -> Result<Option<chrono::NaiveDate>, AdtError> {
    let pid = message
        .segment("PID")
        .ok_or(AdtError::MissingSegment("PID"))?;
    match pid.field(7).filter(|s| !s.is_empty()) {
        None => Ok(None),
        Some(raw) => chrono::NaiveDate::parse_from_str(raw, "%Y%m%d")
            .map(Some)
            .map_err(|_| AdtError::InvalidField("PID-7")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use core_crypto::LocalKeyManager;
    use integrations_hl7v2::parser::parse;

    const ADT_A28: &str =
        "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260719101500||ADT^A28|MSGID0001|P|2.5\r\
PID|1||123456^^^HOPITAL1^PI~2600112233044^^^INS-NIR^NI||DUPONT^JEAN||19800101|M\r\
PV1|1|O\r";

    #[test]
    fn extracts_ins_from_pid3_ins_nir_repetition() {
        let msg = parse(ADT_A28).unwrap();
        assert_eq!(extract_ins(&msg), Ok("2600112233044".to_string()));
    }

    #[test]
    fn missing_ins_nir_repetition_is_missing_ins_error() {
        let msg = parse(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260719101500||ADT^A28|MSGID0001|P|2.5\r\
             PID|1||123456^^^HOPITAL1^PI||DUPONT^JEAN||19800101|M\r",
        )
        .unwrap();
        assert_eq!(extract_ins(&msg), Err(AdtError::MissingIns));
    }

    #[test]
    fn extracts_name_and_birth_date() {
        let msg = parse(ADT_A28).unwrap();
        assert_eq!(
            extract_name(&msg),
            Ok(("JEAN".to_string(), "DUPONT".to_string()))
        );
        assert_eq!(
            extract_birth_date(&msg),
            Ok(Some(chrono::NaiveDate::from_ymd_opt(1980, 1, 1).unwrap()))
        );
    }

    #[test]
    fn missing_pid_is_missing_segment_error() {
        let msg = parse(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260719101500||ADT^A28|MSGID0001|P|2.5\r",
        )
        .unwrap();
        assert_eq!(extract_ins(&msg), Err(AdtError::MissingSegment("PID")));
        assert_eq!(extract_name(&msg), Err(AdtError::MissingSegment("PID")));
        assert_eq!(
            extract_birth_date(&msg),
            Err(AdtError::MissingSegment("PID"))
        );
    }

    #[tokio::test]
    async fn unsupported_trigger_is_invalid_field_without_db() {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://fake@localhost/fake")
            .unwrap();
        let km = LocalKeyManager::new([9u8; 32], "test-v1");
        let msg = parse(ADT_A28).unwrap();
        let result = handle(&pool, Uuid::new_v4(), &km, &msg, "A99").await;
        assert_eq!(
            result,
            Err(AdtError::InvalidField(
                "MSH-9.2 (déclencheur ADT non supporté)"
            ))
        );
    }
}
