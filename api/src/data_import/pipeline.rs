//! Pipeline générique de reprise (DP-F14.a #7179) : applique des lignes
//! normalisées (`ParsedLine`, quel que soit le parseur) dans le tenant, en
//! produisant un rapport ligne à ligne. Même code pour le dry-run et le run :
//! le dry-run exécute TOUT dans une transaction finalement annulée — il
//! voit donc aussi les effets intra-fichier (2 lignes de même clé externe).
//!
//! Idempotence (« re-jouer le même fichier ne crée pas de doublon ») :
//! 1. clé externe `external_ref` (migration 0268, unique par cabinet) ;
//! 2. à défaut, correspondance EXACTE nom + prénom + date de naissance
//!    (insensible à la casse ; naissance `IS NOT DISTINCT FROM`) — documenté
//!    dans `docs/12-api-reference.md` §5.1. Plusieurs homonymes → erreur
//!    ligne (résolution humaine), jamais de rattachement arbitraire.
//!
//! Doublons INS : si la ligne porte un INS, il est chiffré (`encrypt_column`,
//! comme le chemin ADT) + haché, et `patient_merge_candidates::
//! flag_ins_duplicates` ouvre une paire à revue humaine si un autre patient
//! du cabinet partage cet INS — `patient_merge_candidate` ne prend que des
//! raisons INS (CHECK), d'où le match démographique côté pipeline.
//!
//! Isolation des erreurs : une ligne = un SAVEPOINT ; une violation
//! (chevauchement RDV `23P01`, clé externe dupliquée `23505`…) n'annule que
//! sa ligne et devient une entrée `error` du rapport.
//!
//! Performance (done-when : 1 000 patients < 30 s) : les référentiels du
//! cabinet (patients, RDV, praticiens) sont chargés UNE fois en mémoire
//! (`Index`) au début du run et tenus à jour au fil des créations — une
//! ligne coûte alors SAVEPOINT + 1 écriture + RELEASE, pas 2 recherches de
//! plus. Le run est sérialisé par job (`status = 'running'`), l'index n'a
//! donc pas de concurrent dans sa propre transaction.

use std::collections::HashMap;

use chrono::{DateTime, NaiveDate, Utc};
use core_crypto::{encrypt_column, LocalKeyManager};
use serde::{Deserialize, Serialize};
use sqlx::{Acquire, PgPool, Postgres, Row, Transaction};
use uuid::Uuid;

use super::source::{AppointmentRecord, ImportRecord, ParsedLine, PatientLookup, PatientRecord};
use crate::auth::AppError;

/// Issue d'une ligne dans le rapport.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LineAction {
    Created,
    Updated,
    Unchanged,
    Error,
}

/// Une entrée du rapport (`data_import_job.report`). Pas de PII au-delà de
/// la clé externe : les messages citent des colonnes, jamais des valeurs
/// nominatives.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LineOutcome {
    pub line: usize,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub external_ref: Option<String>,
    pub action: LineAction,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub entity_id: Option<Uuid>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
}

#[derive(Debug, Default, Clone, Serialize)]
pub struct Summary {
    pub total: usize,
    pub created: usize,
    pub updated: usize,
    pub unchanged: usize,
    pub errors: usize,
    pub report: Vec<LineOutcome>,
}

impl Summary {
    fn push(&mut self, outcome: LineOutcome) {
        match outcome.action {
            LineAction::Created => self.created += 1,
            LineAction::Updated => self.updated += 1,
            LineAction::Unchanged => self.unchanged += 1,
            LineAction::Error => self.errors += 1,
        }
        self.report.push(outcome);
    }
}

/// Applique `lines` dans le cabinet. `dry_run` = tout est annulé à la fin
/// (rapport identique à ce que ferait le run sur cet état de la base).
///
/// `created_by_secretariat_id` : posé sur les patients créés (#5428) quand
/// l'import est lancé par un secrétariat, sinon `None` — sans quoi la garde
/// R10 (`list_cabinet_patients` / `get_cabinet_patient`) rend invisibles au
/// secrétariat les patients qu'il vient lui-même d'importer (#7480).
pub(crate) async fn apply(
    db: &PgPool,
    cabinet_id: Uuid,
    lines: &[ParsedLine],
    dry_run: bool,
    key_manager: &LocalKeyManager,
    created_by_secretariat_id: Option<Uuid>,
) -> Result<Summary, AppError> {
    let mut tx = db.begin().await.map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let mut index = Index::load(&mut tx, cabinet_id).await?;

    let mut summary = Summary {
        total: lines.len(),
        ..Summary::default()
    };
    for parsed in lines {
        let outcome = match &parsed.record {
            Err(msg) => LineOutcome {
                line: parsed.line,
                external_ref: parsed.external_ref.clone(),
                action: LineAction::Error,
                entity_id: None,
                message: Some(msg.clone()),
            },
            Ok(record) => {
                let mut sp = (&mut tx).begin().await.map_err(|_| AppError::Internal)?;
                let result = match record {
                    ImportRecord::Patient(p) => {
                        apply_patient(
                            &mut sp,
                            &mut index,
                            cabinet_id,
                            p,
                            key_manager,
                            created_by_secretariat_id,
                        )
                        .await
                    }
                    ImportRecord::Appointment(a) => {
                        apply_appointment(&mut sp, &mut index, cabinet_id, a).await
                    }
                };
                match result {
                    Ok((action, entity_id, message)) => {
                        sp.commit().await.map_err(|_| AppError::Internal)?;
                        LineOutcome {
                            line: parsed.line,
                            external_ref: parsed.external_ref.clone(),
                            action,
                            entity_id: Some(entity_id),
                            message,
                        }
                    }
                    Err(LineError::Line(msg)) => {
                        sp.rollback().await.map_err(|_| AppError::Internal)?;
                        LineOutcome {
                            line: parsed.line,
                            external_ref: parsed.external_ref.clone(),
                            action: LineAction::Error,
                            entity_id: None,
                            message: Some(msg),
                        }
                    }
                    Err(LineError::Fatal) => return Err(AppError::Internal),
                }
            }
        };
        summary.push(outcome);
    }

    if dry_run {
        tx.rollback().await.map_err(|_| AppError::Internal)?;
    } else {
        tx.commit().await.map_err(|_| AppError::Internal)?;
    }
    Ok(summary)
}

enum LineError {
    /// Erreur imputable à la ligne (rapport) — la transaction continue.
    Line(String),
    /// Erreur technique (DB injoignable…) — tout le run échoue.
    Fatal,
}

/// SQLSTATE d'une erreur sqlx → erreur ligne lisible, ou fatale.
fn classify(e: sqlx::Error) -> LineError {
    let Some(db) = e.as_database_error() else {
        return LineError::Fatal;
    };
    match db.code().as_deref() {
        Some("23P01") => {
            LineError::Line("chevauchement : le praticien a déjà un RDV sur ce créneau".to_string())
        }
        Some("23505") => LineError::Line(format!(
            "unicité violée ({})",
            db.constraint().unwrap_or("contrainte")
        )),
        Some("23514") | Some("23502") | Some("22P02") | Some("22007") | Some("22008") => {
            LineError::Line(format!("valeur refusée par la base : {}", db.message()))
        }
        _ => LineError::Fatal,
    }
}

type Applied = (LineAction, Uuid, Option<String>);

/// Clé démographique : nom + prénom (casse pliée, espaces bornés) + naissance.
type DemoKey = (String, String, Option<NaiveDate>);

fn demo_key(last: &str, first: &str, birth: Option<NaiveDate>) -> DemoKey {
    (
        last.trim().to_lowercase(),
        first.trim().to_lowercase(),
        birth,
    )
}

/// Référentiels du cabinet en mémoire, chargés une fois par run.
struct Index {
    patients_by_ref: HashMap<String, Uuid>,
    patients_by_demo: HashMap<DemoKey, Vec<Uuid>>,
    appointments_by_ref: HashMap<String, Uuid>,
    /// (patient, praticien, début) → RDV, pour les lignes sans clé externe.
    appointments_by_slot: HashMap<(Uuid, Uuid, DateTime<Utc>), Uuid>,
    practitioners_by_rpps: HashMap<String, Uuid>,
    practitioner_count: usize,
    sole_practitioner: Option<Uuid>,
}

impl Index {
    async fn load(tx: &mut Transaction<'_, Postgres>, cabinet_id: Uuid) -> Result<Self, AppError> {
        let mut index = Index {
            patients_by_ref: HashMap::new(),
            patients_by_demo: HashMap::new(),
            appointments_by_ref: HashMap::new(),
            appointments_by_slot: HashMap::new(),
            practitioners_by_rpps: HashMap::new(),
            practitioner_count: 0,
            sole_practitioner: None,
        };
        let rows = sqlx::query(
            "SELECT id, external_ref, last_name, first_name, birth_date FROM patient \
             WHERE cabinet_id = $1 AND deleted_at IS NULL ORDER BY created_at",
        )
        .bind(cabinet_id)
        .fetch_all(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
        for row in rows {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let ext: Option<String> = row
                .try_get("external_ref")
                .map_err(|_| AppError::Internal)?;
            let last: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            let first: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let birth: Option<NaiveDate> =
                row.try_get("birth_date").map_err(|_| AppError::Internal)?;
            index.insert_patient(id, ext, &last, &first, birth);
        }

        let rows = sqlx::query(
            "SELECT id, external_ref, patient_id, practitioner_id, starts_at FROM appointment \
             WHERE cabinet_id = $1 AND deleted_at IS NULL",
        )
        .bind(cabinet_id)
        .fetch_all(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
        for row in rows {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let ext: Option<String> = row
                .try_get("external_ref")
                .map_err(|_| AppError::Internal)?;
            let patient_id: Uuid = row.try_get("patient_id").map_err(|_| AppError::Internal)?;
            let practitioner_id: Uuid = row
                .try_get("practitioner_id")
                .map_err(|_| AppError::Internal)?;
            let starts_at: DateTime<Utc> =
                row.try_get("starts_at").map_err(|_| AppError::Internal)?;
            index.insert_appointment(id, ext, patient_id, practitioner_id, starts_at);
        }

        let rows = sqlx::query("SELECT id, rpps FROM practitioner WHERE cabinet_id = $1")
            .bind(cabinet_id)
            .fetch_all(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
        index.practitioner_count = rows.len();
        for row in rows {
            let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let rpps: Option<String> = row.try_get("rpps").map_err(|_| AppError::Internal)?;
            if let Some(rpps) = rpps {
                index.practitioners_by_rpps.insert(rpps, id);
            }
            index.sole_practitioner = Some(id);
        }
        if index.practitioner_count != 1 {
            index.sole_practitioner = None;
        }
        Ok(index)
    }

    fn insert_patient(
        &mut self,
        id: Uuid,
        external_ref: Option<String>,
        last: &str,
        first: &str,
        birth: Option<NaiveDate>,
    ) {
        if let Some(ext) = external_ref {
            self.patients_by_ref.insert(ext, id);
        }
        self.patients_by_demo
            .entry(demo_key(last, first, birth))
            .or_default()
            .push(id);
    }

    fn insert_appointment(
        &mut self,
        id: Uuid,
        external_ref: Option<String>,
        patient_id: Uuid,
        practitioner_id: Uuid,
        starts_at: DateTime<Utc>,
    ) {
        if let Some(ext) = external_ref {
            self.appointments_by_ref.insert(ext, id);
        }
        self.appointments_by_slot
            .insert((patient_id, practitioner_id, starts_at), id);
    }

    /// Résolution d'un patient existant : clé externe d'abord, puis
    /// démographie. `Ok(None)` = à créer. `Err(Line)` = homonymes multiples.
    fn find_patient(
        &self,
        lookup: &PatientLookup,
    ) -> Result<Option<(Uuid, &'static str)>, LineError> {
        if let Some(ext) = &lookup.external_ref {
            if let Some(id) = self.patients_by_ref.get(ext) {
                return Ok(Some((*id, "external_ref")));
            }
        }
        let (Some(last), Some(first)) = (&lookup.last_name, &lookup.first_name) else {
            return Ok(None);
        };
        match self
            .patients_by_demo
            .get(&demo_key(last, first, lookup.birth_date))
            .map(Vec::as_slice)
        {
            None | Some([]) => Ok(None),
            Some([id]) => Ok(Some((*id, "demographics"))),
            Some(_) => Err(LineError::Line(
                "plusieurs patients homonymes (nom + prénom + naissance) : rattachement ambigu, \
                 résolution manuelle requise"
                    .to_string(),
            )),
        }
    }
}

fn contact_json(p: &PatientRecord) -> serde_json::Value {
    let mut m = serde_json::Map::new();
    if let Some(v) = &p.phone {
        m.insert("tel".into(), v.clone().into());
    }
    if let Some(v) = &p.email {
        m.insert("email".into(), v.clone().into());
    }
    if let Some(v) = &p.address {
        m.insert("adresse".into(), v.clone().into());
    }
    if let Some(v) = &p.postal_code {
        m.insert("code_postal".into(), v.clone().into());
    }
    if let Some(v) = &p.city {
        m.insert("ville".into(), v.clone().into());
    }
    serde_json::Value::Object(m)
}

async fn apply_patient(
    tx: &mut Transaction<'_, Postgres>,
    index: &mut Index,
    cabinet_id: Uuid,
    p: &PatientRecord,
    key_manager: &LocalKeyManager,
    created_by_secretariat_id: Option<Uuid>,
) -> Result<Applied, LineError> {
    let lookup = PatientLookup {
        external_ref: p.external_ref.clone(),
        last_name: Some(p.last_name.clone()),
        first_name: Some(p.first_name.clone()),
        birth_date: p.birth_date,
    };
    let contact = contact_json(p);

    // INS : chiffré par enveloppe sous le cabinet (comme `hl7v2::adt`),
    // haché pour la détection de doublons (`patient_merge_candidates`).
    let ins = match &p.ins {
        Some(ins) => {
            let enc = encrypt_column(ins.as_bytes(), key_manager, &cabinet_id.to_string())
                .await
                .map_err(|_| LineError::Fatal)?;
            Some((enc, crate::patient_merge_candidates::ins_hash(ins)))
        }
        None => None,
    };

    let existing = index.find_patient(&lookup)?;
    let (action, id, message) = match existing {
        Some((id, matched_by)) => {
            // Rattachement par démographie à un patient déjà porteur d'une
            // AUTRE clé externe : doublon côté source — on ne réécrit pas la
            // clé, on signale.
            let updated = sqlx::query(
                "UPDATE patient \
                 SET first_name = $1, last_name = $2, \
                     birth_date = COALESCE($3, birth_date), \
                     contact = contact || $4::jsonb, \
                     external_ref = COALESCE(external_ref, $5), \
                     updated_at = now() \
                 WHERE id = $6 AND cabinet_id = $7 \
                   AND (first_name IS DISTINCT FROM $1 \
                     OR last_name IS DISTINCT FROM $2 \
                     OR ($3::date IS NOT NULL AND birth_date IS DISTINCT FROM $3::date) \
                     OR NOT (contact @> $4::jsonb) \
                     OR (external_ref IS NULL AND $5::text IS NOT NULL))",
            )
            .bind(&p.first_name)
            .bind(&p.last_name)
            .bind(p.birth_date)
            .bind(&contact)
            .bind(&p.external_ref)
            .bind(id)
            .bind(cabinet_id)
            .execute(&mut **tx)
            .await
            .map_err(classify)?;
            let message = (matched_by == "demographics")
                .then(|| "rattaché à un patient existant (nom + prénom + naissance)".to_string());
            let action = if updated.rows_affected() == 0 {
                LineAction::Unchanged
            } else {
                // La clé externe vient peut-être d'être posée : les lignes
                // suivantes du fichier doivent la retrouver.
                if let Some(ext) = &p.external_ref {
                    index.patients_by_ref.entry(ext.clone()).or_insert(id);
                }
                LineAction::Updated
            };
            (action, id, message)
        }
        None => {
            let row = sqlx::query(
                "INSERT INTO patient \
                   (cabinet_id, first_name, last_name, birth_date, contact, external_ref, created_by_secretariat_id) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id",
            )
            .bind(cabinet_id)
            .bind(&p.first_name)
            .bind(&p.last_name)
            .bind(p.birth_date)
            .bind(&contact)
            .bind(&p.external_ref)
            .bind(created_by_secretariat_id)
            .fetch_one(&mut **tx)
            .await
            .map_err(classify)?;
            let id: Uuid = row.try_get("id").map_err(|_| LineError::Fatal)?;
            index.insert_patient(
                id,
                p.external_ref.clone(),
                &p.last_name,
                &p.first_name,
                p.birth_date,
            );
            (LineAction::Created, id, None)
        }
    };

    if let Some((enc, hash)) = ins {
        // Jamais d'écrasement d'un INS déjà connu (vérifié par un canal
        // plus fiable — ADT/INSi) par une valeur de reprise.
        sqlx::query(
            "UPDATE patient SET ins_ciphertext = $1, ins_key_ref = $2, ins_hash = $3 \
             WHERE id = $4 AND cabinet_id = $5 AND ins_ciphertext IS NULL",
        )
        .bind(&enc.ciphertext)
        .bind(&enc.key_ref)
        .bind(&hash)
        .bind(id)
        .bind(cabinet_id)
        .execute(&mut **tx)
        .await
        .map_err(classify)?;
        if let Some(hash) = hash {
            crate::patient_merge_candidates::flag_ins_duplicates(tx, cabinet_id, id, &hash)
                .await
                .map_err(classify)?;
        }
    }

    Ok((action, id, message))
}

async fn apply_appointment(
    tx: &mut Transaction<'_, Postgres>,
    index: &mut Index,
    cabinet_id: Uuid,
    a: &AppointmentRecord,
) -> Result<Applied, LineError> {
    let Some((patient_id, _)) = index.find_patient(&a.patient)? else {
        return Err(LineError::Line(
            "patient introuvable (importer d'abord les patients, ou vérifier \
             `patient_ref_externe` / nom + prénom + naissance)"
                .to_string(),
        ));
    };

    let practitioner_id: Uuid = match &a.practitioner_rpps {
        Some(rpps) => *index.practitioners_by_rpps.get(rpps).ok_or_else(|| {
            LineError::Line("praticien introuvable pour ce `praticien_rpps`".to_string())
        })?,
        // Sans RPPS : cabinet mono-praticien uniquement, sinon ambigu.
        None => index.sole_practitioner.ok_or_else(|| {
            LineError::Line(
                "`praticien_rpps` obligatoire : le cabinet compte plusieurs praticiens \
                 (ou aucun)"
                    .to_string(),
            )
        })?,
    };

    let existing = match &a.external_ref {
        Some(ext) => index.appointments_by_ref.get(ext).copied(),
        // Sans clé externe : même patient + même praticien + même début.
        None => index
            .appointments_by_slot
            .get(&(patient_id, practitioner_id, a.starts_at))
            .copied(),
    };

    let cancelled_at = (a.status == "cancelled").then(Utc::now);
    match existing {
        Some(id) => {
            let updated = sqlx::query(
                "UPDATE appointment \
                 SET patient_id = $1, practitioner_id = $2, starts_at = $3, ends_at = $4, \
                     status = $5, motif = $6, \
                     cancelled_at = CASE WHEN $5 = 'cancelled' THEN COALESCE(cancelled_at, $8) \
                                         ELSE NULL END, \
                     updated_at = now() \
                 WHERE id = $7 AND cabinet_id = $9 \
                   AND (patient_id <> $1 OR practitioner_id <> $2 OR starts_at <> $3 \
                     OR ends_at <> $4 OR status <> $5 OR motif IS DISTINCT FROM $6)",
            )
            .bind(patient_id)
            .bind(practitioner_id)
            .bind(a.starts_at)
            .bind(a.ends_at)
            .bind(&a.status)
            .bind(&a.motif)
            .bind(id)
            .bind(cancelled_at)
            .bind(cabinet_id)
            .execute(&mut **tx)
            .await
            .map_err(classify)?;
            let action = if updated.rows_affected() == 0 {
                LineAction::Unchanged
            } else {
                index.insert_appointment(
                    id,
                    a.external_ref.clone(),
                    patient_id,
                    practitioner_id,
                    a.starts_at,
                );
                LineAction::Updated
            };
            Ok((action, id, None))
        }
        None => {
            let row = sqlx::query(
                "INSERT INTO appointment \
                   (cabinet_id, patient_id, practitioner_id, starts_at, ends_at, status, \
                    motif, external_ref, cancelled_at) \
                 VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9) RETURNING id",
            )
            .bind(cabinet_id)
            .bind(patient_id)
            .bind(practitioner_id)
            .bind(a.starts_at)
            .bind(a.ends_at)
            .bind(&a.status)
            .bind(&a.motif)
            .bind(&a.external_ref)
            .bind(cancelled_at)
            .fetch_one(&mut **tx)
            .await
            .map_err(classify)?;
            let id: Uuid = row.try_get("id").map_err(|_| LineError::Fatal)?;
            index.insert_appointment(
                id,
                a.external_ref.clone(),
                patient_id,
                practitioner_id,
                a.starts_at,
            );
            Ok((LineAction::Created, id, None))
        }
    }
}
