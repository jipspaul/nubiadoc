//! Parseur CSV de reprise (DP-F14.a #7179) — premier `ImportSource`.
//!
//! Format (documenté dans `docs/12-api-reference.md` §5.1 et illustré par
//! `api/tests/fixtures/import/patients.csv` / `appointments.csv`) :
//! - séparateur `;`, encodage UTF-8 (BOM toléré), 1re ligne = en-têtes en
//!   français (insensibles à la casse et aux accents, `_` ou espace) ;
//! - dates `JJ/MM/AAAA` (ou ISO `AAAA-MM-JJ`) ; horodatages `JJ/MM/AAAA HH:MM`
//!   en heure locale `Europe/Paris` (ou RFC 3339 avec décalage explicite) ;
//! - colonnes inconnues ignorées, colonnes optionnelles vides = absentes.
//!
//! Compatible avec les exports « patients » / « rendez-vous » Doctolib
//! (mêmes intitulés une fois normalisés).

use chrono::{DateTime, NaiveDate, NaiveDateTime, TimeZone, Utc};

use super::source::{
    AppointmentRecord, ImportKind, ImportRecord, ImportSource, ParseError, ParsedLine,
    PatientLookup, PatientRecord,
};

pub struct CsvSource {
    kind: ImportKind,
}

impl CsvSource {
    pub fn patients() -> Self {
        Self {
            kind: ImportKind::CsvPatients,
        }
    }

    pub fn appointments() -> Self {
        Self {
            kind: ImportKind::CsvAppointments,
        }
    }
}

/// Colonnes obligatoires par format (noms normalisés).
const PATIENT_REQUIRED: &[&str] = &["nom", "prenom"];
const APPOINTMENT_REQUIRED: &[&str] = &["debut"];

const MAX_FIELD_LEN: usize = 256;

impl ImportSource for CsvSource {
    fn kind(&self) -> ImportKind {
        self.kind
    }

    fn parse(&self, bytes: &[u8]) -> Result<Vec<ParsedLine>, ParseError> {
        if bytes.iter().all(u8::is_ascii_whitespace) {
            return Err(ParseError::Empty);
        }
        let text = std::str::from_utf8(bytes).map_err(|_| ParseError::Encoding)?;
        let text = text.strip_prefix('\u{feff}').unwrap_or(text);

        let mut reader = csv::ReaderBuilder::new()
            .delimiter(b';')
            .flexible(true)
            .trim(csv::Trim::All)
            .has_headers(true)
            .from_reader(text.as_bytes());

        let headers: Vec<String> = reader
            .headers()
            .map_err(|e| ParseError::Malformed(e.to_string()))?
            .iter()
            .map(normalize_header)
            .collect();
        let required = match self.kind {
            ImportKind::CsvPatients => PATIENT_REQUIRED,
            ImportKind::CsvAppointments => APPOINTMENT_REQUIRED,
        };
        let missing: Vec<&str> = required
            .iter()
            .copied()
            .filter(|c| !headers.iter().any(|h| h == c))
            .collect();
        if !missing.is_empty() {
            return Err(ParseError::MissingColumns(missing.join(", ")));
        }

        let mut lines = Vec::new();
        for (idx, row) in reader.records().enumerate() {
            let line = idx + 2; // 1 = en-têtes
            let row = match row {
                Ok(r) => r,
                Err(e) => {
                    lines.push(ParsedLine {
                        line,
                        external_ref: None,
                        record: Err(format!("ligne illisible : {e}")),
                    });
                    continue;
                }
            };
            if row.iter().all(|c| c.trim().is_empty()) {
                continue; // ligne vide : ignorée silencieusement
            }
            let fields = Fields {
                headers: &headers,
                row: &row,
            };
            let external_ref = fields.opt("ref_externe");
            let record = match self.kind {
                ImportKind::CsvPatients => parse_patient(&fields).map(ImportRecord::Patient),
                ImportKind::CsvAppointments => {
                    parse_appointment(&fields).map(ImportRecord::Appointment)
                }
            };
            lines.push(ParsedLine {
                line,
                external_ref,
                record,
            });
        }
        if lines.is_empty() {
            return Err(ParseError::Empty);
        }
        Ok(lines)
    }
}

/// `Prénom` → `prenom`, `Date de naissance` → `date_naissance`, `Téléphone`
/// → `telephone` : casse, accents, espaces, puis quelques alias courants
/// (exports Doctolib / tableurs) vers le nom canonique documenté.
fn normalize_header(raw: &str) -> String {
    let key = fold_ascii(raw);
    let canonical = match key.as_str() {
        "date_de_naissance" | "naissance" | "ne_le" | "nee_le" => "date_naissance",
        "tel" | "portable" | "mobile" | "telephone_portable" => "telephone",
        "courriel" | "e_mail" | "mail" => "email",
        "id" | "identifiant" | "reference" | "ref" => "ref_externe",
        "cp" => "code_postal",
        "rpps" => "praticien_rpps",
        "date_debut" | "date_heure" | "date" | "start" => "debut",
        "date_fin" | "end" => "fin",
        "duree" | "duree_minutes" => "duree_min",
        "status" | "etat" => "statut",
        "patient_id" | "id_patient" | "patient_ref" | "patient" => "patient_ref_externe",
        other => other,
    };
    canonical.to_string()
}

fn fold_ascii(raw: &str) -> String {
    raw.trim()
        .to_lowercase()
        .chars()
        .map(|c| match c {
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'à' | 'â' | 'ä' => 'a',
            'î' | 'ï' => 'i',
            'ô' | 'ö' => 'o',
            'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            ' ' | '-' | '.' => '_',
            other => other,
        })
        .collect::<String>()
        .trim_matches('_')
        .to_string()
}

struct Fields<'a> {
    headers: &'a [String],
    row: &'a csv::StringRecord,
}

impl Fields<'_> {
    /// Valeur d'une colonne ; `None` si absente ou vide.
    fn opt(&self, name: &str) -> Option<String> {
        let idx = self.headers.iter().position(|h| h == name)?;
        let v = self.row.get(idx)?.trim();
        if v.is_empty() {
            None
        } else {
            Some(v.chars().take(MAX_FIELD_LEN).collect())
        }
    }

    fn required(&self, name: &str) -> Result<String, String> {
        self.opt(name)
            .ok_or_else(|| format!("colonne `{name}` obligatoire vide"))
    }
}

fn parse_patient(f: &Fields<'_>) -> Result<PatientRecord, String> {
    let last_name = f.required("nom")?;
    let first_name = f.required("prenom")?;
    let birth_date = f
        .opt("date_naissance")
        .map(|d| parse_date(&d))
        .transpose()?;
    let email = f.opt("email");
    if let Some(e) = &email {
        if !e.contains('@') {
            return Err("email invalide".to_string());
        }
    }
    let ins = f.opt("ins");
    if let Some(i) = &ins {
        if i.len() != 15 || !i.chars().all(|c| c.is_ascii_digit()) {
            return Err("ins invalide : 15 chiffres attendus".to_string());
        }
    }
    Ok(PatientRecord {
        external_ref: f.opt("ref_externe"),
        last_name,
        first_name,
        birth_date,
        phone: f.opt("telephone"),
        email,
        address: f.opt("adresse"),
        postal_code: f.opt("code_postal"),
        city: f.opt("ville"),
        ins,
    })
}

fn parse_appointment(f: &Fields<'_>) -> Result<AppointmentRecord, String> {
    let patient = PatientLookup {
        external_ref: f.opt("patient_ref_externe"),
        last_name: f.opt("nom"),
        first_name: f.opt("prenom"),
        birth_date: f
            .opt("date_naissance")
            .map(|d| parse_date(&d))
            .transpose()?,
    };
    if patient.external_ref.is_none()
        && (patient.last_name.is_none() || patient.first_name.is_none())
    {
        return Err(
            "patient non identifiable : `patient_ref_externe` ou `nom` + `prenom` requis"
                .to_string(),
        );
    }
    let starts_at = parse_datetime(&f.required("debut")?)?;
    let ends_at = match (f.opt("fin"), f.opt("duree_min")) {
        (Some(fin), _) => parse_datetime(&fin)?,
        (None, Some(d)) => {
            let minutes: i64 = d
                .parse()
                .map_err(|_| "duree_min invalide : entier de minutes attendu".to_string())?;
            if !(1..=24 * 60).contains(&minutes) {
                return Err("duree_min hors bornes (1..1440)".to_string());
            }
            starts_at + chrono::Duration::minutes(minutes)
        }
        (None, None) => starts_at + chrono::Duration::minutes(30),
    };
    if ends_at <= starts_at {
        return Err("fin antérieure ou égale au début".to_string());
    }
    let status = map_status(f.opt("statut").as_deref(), starts_at)?;
    Ok(AppointmentRecord {
        external_ref: f.opt("ref_externe"),
        patient,
        practitioner_rpps: f.opt("praticien_rpps"),
        starts_at,
        ends_at,
        status,
        motif: f.opt("motif"),
    })
}

/// Statut source (libellés français ou valeurs de l'énum) → `appointment.status`.
/// Vide : `done` si passé, `confirmed` sinon.
fn map_status(raw: Option<&str>, starts_at: DateTime<Utc>) -> Result<String, String> {
    let Some(raw) = raw else {
        return Ok(if starts_at < Utc::now() {
            "done".to_string()
        } else {
            "confirmed".to_string()
        });
    };
    let key = fold_ascii(raw);
    let mapped = match key.as_str() {
        "confirme" | "planifie" | "programme" | "a_venir" | "confirmed" => "confirmed",
        "honore" | "termine" | "realise" | "effectue" | "done" => "done",
        "annule" | "cancelled" | "canceled" => "cancelled",
        "absent" | "lapin" | "non_honore" | "no_show" => "no_show",
        "demande" | "requested" => "requested",
        "en_cours" | "in_progress" => "in_progress",
        "arrive" | "checked_in" => "checked_in",
        _ => return Err(format!("statut inconnu : `{raw}`")),
    };
    Ok(mapped.to_string())
}

/// `JJ/MM/AAAA`, `JJ-MM-AAAA` ou `AAAA-MM-JJ`.
pub(crate) fn parse_date(raw: &str) -> Result<NaiveDate, String> {
    let raw = raw.trim();
    for fmt in ["%d/%m/%Y", "%d-%m-%Y", "%Y-%m-%d", "%d/%m/%y"] {
        if let Ok(d) = NaiveDate::parse_from_str(raw, fmt) {
            return Ok(d);
        }
    }
    Err(format!("date invalide : `{raw}` (JJ/MM/AAAA attendu)"))
}

/// `JJ/MM/AAAA HH:MM[:SS]` ou `AAAA-MM-JJ[ T]HH:MM[:SS]` en heure locale
/// `Europe/Paris`, ou RFC 3339 avec décalage explicite.
pub(crate) fn parse_datetime(raw: &str) -> Result<DateTime<Utc>, String> {
    let raw = raw.trim();
    if let Ok(dt) = DateTime::parse_from_rfc3339(raw) {
        return Ok(dt.with_timezone(&Utc));
    }
    for fmt in [
        "%d/%m/%Y %H:%M:%S",
        "%d/%m/%Y %H:%M",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
    ] {
        if let Ok(ndt) = NaiveDateTime::parse_from_str(raw, fmt) {
            return Ok(paris_local_to_utc(ndt));
        }
    }
    Err(format!(
        "horodatage invalide : `{raw}` (JJ/MM/AAAA HH:MM attendu)"
    ))
}

/// Heure locale `Europe/Paris` → UTC (règle UE été/hiver, cf. `scheduling`).
fn paris_local_to_utc(ndt: NaiveDateTime) -> DateTime<Utc> {
    let offset = crate::scheduling::paris_utc_offset_hours(ndt.date());
    Utc.from_utc_datetime(&ndt) - chrono::Duration::hours(offset)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_header_handles_accents_and_spaces() {
        assert_eq!(normalize_header(" Prénom "), "prenom");
        assert_eq!(normalize_header("Date de naissance"), "date_naissance");
        assert_eq!(normalize_header("Téléphone"), "telephone");
        assert_eq!(normalize_header("ref_externe"), "ref_externe");
    }

    #[test]
    fn parses_patients_with_bom_and_french_headers() {
        let csv = "\u{feff}Ref_Externe;Nom;Prénom;Date de naissance;Téléphone;Email\n\
                   P1;Durand;Alice;03/04/1985;0601020304;alice@example.test\n\
                   ;Martin;Bob;;;\n\
                   P3;;Carl;;;\n";
        let lines = CsvSource::patients().parse(csv.as_bytes()).unwrap();
        assert_eq!(lines.len(), 3);
        match &lines[0].record {
            Ok(ImportRecord::Patient(p)) => {
                assert_eq!(p.external_ref.as_deref(), Some("P1"));
                assert_eq!(p.last_name, "Durand");
                assert_eq!(p.birth_date, NaiveDate::from_ymd_opt(1985, 4, 3));
                assert_eq!(p.phone.as_deref(), Some("0601020304"));
            }
            other => panic!("attendu patient, obtenu {other:?}"),
        }
        assert!(lines[1].record.is_ok());
        assert_eq!(lines[1].external_ref, None);
        assert!(lines[2].record.as_ref().unwrap_err().contains("nom"));
        assert_eq!(lines[2].line, 4);
    }

    #[test]
    fn missing_required_column_is_a_file_error() {
        let err = CsvSource::patients()
            .parse(b"ref_externe;prenom\nP1;Alice\n")
            .unwrap_err();
        assert_eq!(err, ParseError::MissingColumns("nom".to_string()));
        assert_eq!(
            CsvSource::patients().parse(b"  \n").unwrap_err(),
            ParseError::Empty
        );
    }

    #[test]
    fn parses_appointments_local_time_and_status() {
        let csv = "ref_externe;patient_ref_externe;praticien_rpps;debut;duree_min;statut;motif\n\
                   R1;P1;10001234567;15/07/2030 09:00;30;confirmé;Détartrage\n\
                   R2;P1;10001234567;2030-01-15T09:00:00;;honoré;\n\
                   R3;;10001234567;15/07/2030 10:00;30;bizarre;\n";
        let lines = CsvSource::appointments().parse(csv.as_bytes()).unwrap();
        let Ok(ImportRecord::Appointment(a)) = &lines[0].record else {
            panic!("attendu RDV");
        };
        // Juillet = CEST (+2) : 09:00 Paris = 07:00 UTC.
        assert_eq!(a.starts_at.to_rfc3339(), "2030-07-15T07:00:00+00:00");
        assert_eq!(a.ends_at - a.starts_at, chrono::Duration::minutes(30));
        assert_eq!(a.status, "confirmed");
        let Ok(ImportRecord::Appointment(b)) = &lines[1].record else {
            panic!("attendu RDV");
        };
        // Janvier = CET (+1) : 09:00 Paris = 08:00 UTC, durée par défaut 30 min.
        assert_eq!(b.starts_at.to_rfc3339(), "2030-01-15T08:00:00+00:00");
        assert_eq!(b.status, "done");
        // Patient non identifiable (ni ref ni nom/prénom) → erreur ligne.
        assert!(lines[2].record.is_err());
    }
}
