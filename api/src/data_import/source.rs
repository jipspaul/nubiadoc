//! Contrat d'une source de reprise de données (`ImportSource`, DP-F14.a
//! #7179) : un parseur transforme un fichier brut en lignes NORMALISÉES,
//! indépendantes du format d'origine. Le pipeline (`pipeline.rs`) ne
//! connaît que ces lignes — brancher un nouveau format (DSIO, DP-F14.b ;
//! export Logos…) = une nouvelle impl de ce trait, zéro changement dans le
//! pipeline, les handlers ou le rapport.
//!
//! Le parseur est synchrone et en mémoire (fichiers de reprise : quelques
//! milliers de lignes, ≤ `MAX_UPLOAD_SIZE`) ; il rend UNE entrée par ligne
//! source, y compris les lignes invalides (`ParsedLine::record = Err`), pour
//! que le rapport reste ligne à ligne.

use chrono::{DateTime, NaiveDate, Utc};
use serde::{Deserialize, Serialize};

/// Format/parseur d'un job d'import — valeur de `data_import_job.kind`
/// (CHECK, migration 0268).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportKind {
    CsvPatients,
    CsvAppointments,
}

impl ImportKind {
    pub fn as_str(self) -> &'static str {
        match self {
            ImportKind::CsvPatients => "csv_patients",
            ImportKind::CsvAppointments => "csv_appointments",
        }
    }

    pub fn parse(raw: &str) -> Option<Self> {
        match raw.trim() {
            "csv_patients" => Some(ImportKind::CsvPatients),
            "csv_appointments" => Some(ImportKind::CsvAppointments),
            _ => None,
        }
    }
}

/// Patient normalisé (fiche administrative — la reprise ne porte AUCUNE
/// donnée clinique). `ins` est le seul champ qui sera chiffré en base.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PatientRecord {
    pub external_ref: Option<String>,
    pub last_name: String,
    pub first_name: String,
    pub birth_date: Option<NaiveDate>,
    pub phone: Option<String>,
    pub email: Option<String>,
    pub address: Option<String>,
    pub postal_code: Option<String>,
    pub city: Option<String>,
    pub ins: Option<String>,
}

/// Identité du patient d'un RDV : par clé externe (patient importé avec
/// `ref_externe`) et/ou par démographie (nom + prénom + date de naissance).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PatientLookup {
    pub external_ref: Option<String>,
    pub last_name: Option<String>,
    pub first_name: Option<String>,
    pub birth_date: Option<NaiveDate>,
}

/// RDV normalisé. `starts_at`/`ends_at` déjà en UTC (le parseur porte la
/// convention de fuseau de son format — CSV : `Europe/Paris`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppointmentRecord {
    pub external_ref: Option<String>,
    pub patient: PatientLookup,
    pub practitioner_rpps: Option<String>,
    pub starts_at: DateTime<Utc>,
    pub ends_at: DateTime<Utc>,
    /// Valeur de l'énum `appointment.status` (déjà mappée par le parseur).
    pub status: String,
    pub motif: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ImportRecord {
    Patient(PatientRecord),
    Appointment(AppointmentRecord),
}

/// Une ligne source, valide ou non. `line` = numéro humain (1 = en-tête).
#[derive(Debug, Clone)]
pub struct ParsedLine {
    pub line: usize,
    pub external_ref: Option<String>,
    pub record: Result<ImportRecord, String>,
}

/// Erreur fichier (pas ligne) : le fichier entier est inexploitable.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ParseError {
    #[error("fichier vide")]
    Empty,
    #[error("encodage invalide : UTF-8 attendu")]
    Encoding,
    #[error("colonnes obligatoires absentes : {0}")]
    MissingColumns(String),
    #[error("fichier illisible : {0}")]
    Malformed(String),
}

/// Contrat d'un parseur. Un parseur = un `ImportKind`.
pub trait ImportSource: Send + Sync {
    fn kind(&self) -> ImportKind;

    /// Parse le fichier entier. `Err` = fichier inexploitable (le job passe
    /// en `failed`) ; `Ok` = une entrée par ligne de données, dans l'ordre.
    fn parse(&self, bytes: &[u8]) -> Result<Vec<ParsedLine>, ParseError>;
}

/// Résout le parseur d'un `kind`. Point d'extension unique : ajouter un
/// format = une nouvelle branche ici + son module.
pub fn source_for(kind: ImportKind) -> Box<dyn ImportSource> {
    match kind {
        ImportKind::CsvPatients => Box::new(super::csv::CsvSource::patients()),
        ImportKind::CsvAppointments => Box::new(super::csv::CsvSource::appointments()),
    }
}
