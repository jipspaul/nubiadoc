//! Mapping `ADT^A28`/`A31`/`A08` → référentiel patient (lot B8, #3927),
//! appelé par `dispatch::process_message` pour tout message du groupe `ADT`.
//!
//! Quoi : synchronisation entrante du référentiel patient depuis le SIH
//! partenaire — `A28` crée un patient dans le cabinet résolu (B6), `A31` et
//! `A08` mettent à jour la démographie d'un patient existant, résolu par INS.
//! Quand : à chaque message MLLP du groupe ADT (listener B10 → dispatch B7).
//! Pourquoi cette approche : l'INS est extrait de `PID-3` (répétition dont
//! l'autorité d'affectation, composant 4, vaut `INS-NIR`), chiffré via
//! `core_crypto::encrypt_column` sous le contexte du cabinet (colonne
//! `patient.ins_ciphertext`, migration 0003) et **jamais loggé en clair**.
//! La résolution par INS (A31/A08) déchiffre-compare les patients du cabinet
//! porteurs d'un INS — même compromis O(patientèle) que la recherche FHIR A4
//! (`interop::patient`, invérifiable en SQL par construction).
//! Modes d'échec : [`AdtError`] — `Display` fournit le texte `MSA-3` (ACK
//! `AE`), fail-closed, jamais de détail DB brut ni d'INS dans les messages.

use chrono::NaiveDate;
use core_crypto::{decrypt_column, encrypt_column, KeyManager, LocalKeyManager};
use integrations_hl7v2::message::Message;
use sqlx::{PgPool, Row};
use thiserror::Error;
use uuid::Uuid;

/// Autorité d'affectation attendue en `PID-3.4` pour l'INS (référentiel ANS).
const INS_ASSIGNING_AUTHORITY: &str = "INS-NIR";

/// Erreur de mapping/traitement ADT — texte renvoyé en `MSA-3` (ACK `AE`).
#[derive(Debug, Error)]
pub enum AdtError {
    #[error("segment {0} manquant")]
    MissingSegment(&'static str),
    #[error("champ {0} manquant ou invalide")]
    InvalidField(&'static str),
    #[error("aucune répétition PID-3 avec l'autorité INS-NIR")]
    MissingIns,
    #[error("INS mal formé (15 chiffres attendus)")]
    MalformedIns,
    #[error("type de message ADT non reconnu : {0}")]
    UnsupportedMessageType(String),
    #[error("patient INS introuvable dans ce cabinet (A31/A08 sur un patient jamais créé — envoyer un A28 d'abord)")]
    PatientNotFound,
    #[error("chiffrement INS indisponible (KMS_MASTER_KEY)")]
    Crypto,
    #[error("erreur interne")]
    Internal,
}

/// Identité extraite du `PID` — l'INS n'apparaît dans aucun `Debug`/log.
struct PidIdentity {
    ins: String,
    first_name: String,
    last_name: String,
    birth_date: Option<NaiveDate>,
}

/// Point d'entrée appelé par `dispatch::process_message` pour le groupe ADT.
pub async fn handle(
    db: &PgPool,
    cabinet_id: Uuid,
    message: &Message,
    message_type: &str,
) -> Result<(), AdtError> {
    let trigger = message_type
        .split('^')
        .nth(1)
        .ok_or_else(|| AdtError::UnsupportedMessageType(message_type.to_string()))?;

    let identity = parse_pid(message)?;
    match trigger {
        "A28" => create_patient(db, cabinet_id, identity).await,
        "A31" | "A08" => update_patient(db, cabinet_id, identity).await,
        other => Err(AdtError::UnsupportedMessageType(other.to_string())),
    }
}

/// Même convention que `interop::patient` / `auth::login` : clé maître locale
/// (POC/dev) depuis `KMS_MASTER_KEY` (32 octets base64). Jamais de fallback
/// en clair.
fn key_manager_from_env() -> Result<LocalKeyManager, AdtError> {
    use base64::engine::{general_purpose::STANDARD, Engine};
    let raw = std::env::var("KMS_MASTER_KEY").map_err(|_| AdtError::Crypto)?;
    let decoded = STANDARD.decode(raw.trim()).map_err(|_| AdtError::Crypto)?;
    let key: [u8; 32] = decoded.try_into().map_err(|_| AdtError::Crypto)?;
    Ok(LocalKeyManager::new(
        key,
        std::env::var("KMS_KEY_VERSION").unwrap_or_else(|_| "v1".to_string()),
    ))
}

/// Extrait identité + INS du segment `PID`.
///
/// - `PID-3` : répétitions CX — on retient celle dont le composant 4
///   (assigning authority) vaut `INS-NIR` ; composant 1 = valeur.
/// - `PID-5` : `family^given`.
/// - `PID-7` : date de naissance `YYYYMMDD` (préfixe, l'heure est ignorée).
fn parse_pid(message: &Message) -> Result<PidIdentity, AdtError> {
    let pid = message
        .segment("PID")
        .ok_or(AdtError::MissingSegment("PID"))?;

    let mut ins: Option<String> = None;
    if let Some(reps) = pid.repetitions(3) {
        for (i, _) in reps.enumerate() {
            let authority = pid.component_in_repetition(3, i + 1, 4).unwrap_or("");
            if authority == INS_ASSIGNING_AUTHORITY {
                ins = pid.component_in_repetition(3, i + 1, 1).map(str::to_string);
                break;
            }
        }
    }
    let ins = ins.ok_or(AdtError::MissingIns)?;
    if ins.len() != 15 || !ins.bytes().all(|b| b.is_ascii_digit()) {
        return Err(AdtError::MalformedIns);
    }

    let last_name = pid
        .component(5, 1)
        .filter(|s| !s.trim().is_empty())
        .map(str::to_string)
        .ok_or(AdtError::InvalidField("PID-5.1"))?;
    let first_name = pid
        .component(5, 2)
        .filter(|s| !s.trim().is_empty())
        .map(str::to_string)
        .ok_or(AdtError::InvalidField("PID-5.2"))?;

    let birth_date = match pid.field(7).map(str::trim).filter(|s| !s.is_empty()) {
        Some(raw) => Some(
            NaiveDate::parse_from_str(raw.get(..8).unwrap_or(raw), "%Y%m%d")
                .map_err(|_| AdtError::InvalidField("PID-7"))?,
        ),
        None => None,
    };

    Ok(PidIdentity {
        ins,
        first_name,
        last_name,
        birth_date,
    })
}

/// Résout le patient du cabinet porteur de cet INS : déchiffre-compare chaque
/// patient à INS renseigné (O(patientèle), même compromis que la recherche
/// FHIR A4 — l'INS chiffré par enveloppe est invérifiable en SQL).
async fn find_patient_by_ins(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    cabinet_id: Uuid,
    ins: &str,
    key_manager: &dyn KeyManager,
) -> Result<Option<Uuid>, AdtError> {
    let rows = sqlx::query(
        "SELECT id, ins_ciphertext, ins_key_ref FROM patient \
         WHERE cabinet_id = $1 AND ins_ciphertext IS NOT NULL AND deleted_at IS NULL",
    )
    .bind(cabinet_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(|_| AdtError::Internal)?;

    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| AdtError::Internal)?;
        let ciphertext: Vec<u8> = row
            .try_get("ins_ciphertext")
            .map_err(|_| AdtError::Internal)?;
        let key_ref: String = row.try_get("ins_key_ref").map_err(|_| AdtError::Internal)?;
        if let Ok(plaintext) =
            decrypt_column(&ciphertext, key_manager, &cabinet_id.to_string(), &key_ref).await
        {
            if plaintext == ins.as_bytes() {
                return Ok(Some(id));
            }
        }
    }
    Ok(None)
}

/// `A28` : crée le patient. Si un patient du cabinet porte déjà cet INS, le
/// message est idempotent (mise à jour démographique, pas de doublon créé).
async fn create_patient(
    db: &PgPool,
    cabinet_id: Uuid,
    identity: PidIdentity,
) -> Result<(), AdtError> {
    let key_manager = key_manager_from_env()?;
    let encrypted = encrypt_column(
        identity.ins.as_bytes(),
        &key_manager,
        &cabinet_id.to_string(),
    )
    .await
    .map_err(|_| AdtError::Crypto)?;

    let mut tx = begin_tenant_tx(db, cabinet_id).await?;
    match find_patient_by_ins(&mut tx, cabinet_id, &identity.ins, &key_manager).await? {
        Some(patient_id) => apply_demographics(&mut tx, patient_id, &identity).await?,
        None => {
            let row = sqlx::query(
                "INSERT INTO patient \
                   (cabinet_id, first_name, last_name, birth_date, ins_ciphertext, \
                    ins_key_ref, ins_hash) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7) \
                 RETURNING id",
            )
            .bind(cabinet_id)
            .bind(&identity.first_name)
            .bind(&identity.last_name)
            .bind(identity.birth_date)
            .bind(&encrypted.ciphertext)
            .bind(&encrypted.key_ref)
            .bind(crate::patient_merge_candidates::ins_hash(&identity.ins))
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AdtError::Internal)?;
            // A5 (#3916) : flagge les doublons d'INS (paires à revue humaine).
            // Sans KMS_MASTER_KEY le hash est None -> détection sautée, jamais
            // bloquante pour l'ingestion elle-même.
            let new_id: Uuid = row.try_get("id").map_err(|_| AdtError::Internal)?;
            if let Some(hash) = crate::patient_merge_candidates::ins_hash(&identity.ins) {
                crate::patient_merge_candidates::flag_ins_duplicates(
                    &mut tx, cabinet_id, new_id, &hash,
                )
                .await
                .map_err(|_| AdtError::Internal)?;
            }
        }
    }
    tx.commit().await.map_err(|_| AdtError::Internal)?;
    Ok(())
}

/// `A31`/`A08` : met à jour la démographie du patient résolu par INS.
async fn update_patient(
    db: &PgPool,
    cabinet_id: Uuid,
    identity: PidIdentity,
) -> Result<(), AdtError> {
    let key_manager = key_manager_from_env()?;
    let mut tx = begin_tenant_tx(db, cabinet_id).await?;
    let patient_id = find_patient_by_ins(&mut tx, cabinet_id, &identity.ins, &key_manager)
        .await?
        .ok_or(AdtError::PatientNotFound)?;
    apply_demographics(&mut tx, patient_id, &identity).await?;
    tx.commit().await.map_err(|_| AdtError::Internal)?;
    Ok(())
}

/// Ouvre une transaction RLS-scopée (`app.current_cabinet_id`) — même
/// convention que `core_tenancy::with_tenant`, en direct pour garder les
/// erreurs métier [`AdtError`] intactes.
async fn begin_tenant_tx(
    db: &PgPool,
    cabinet_id: Uuid,
) -> Result<sqlx::Transaction<'static, sqlx::Postgres>, AdtError> {
    let mut tx = db.begin().await.map_err(|_| AdtError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AdtError::Internal)?;
    Ok(tx)
}

async fn apply_demographics(
    tx: &mut sqlx::Transaction<'static, sqlx::Postgres>,
    patient_id: Uuid,
    identity: &PidIdentity,
) -> Result<(), AdtError> {
    sqlx::query(
        "UPDATE patient \
         SET first_name = $1, last_name = $2, \
             birth_date = COALESCE($3, birth_date), updated_at = now() \
         WHERE id = $4",
    )
    .bind(&identity.first_name)
    .bind(&identity.last_name)
    .bind(identity.birth_date)
    .bind(patient_id)
    .execute(&mut **tx)
    .await
    .map_err(|_| AdtError::Internal)?;
    Ok(())
}
