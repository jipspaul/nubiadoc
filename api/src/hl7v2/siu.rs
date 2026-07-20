//! Mapping `SIU^S12`/`S14`/`S15` → service rendez-vous (lot B9), appelé par
//! `dispatch::process_message` pour tout message du groupe `SIU`.
//!
//! ## Portée de cette tranche
//!
//! - **`SIU^S12`** (nouveau RDV) : implémenté, via
//!   [`crate::interop::appointment::create_appointment_service`] (la même
//!   fonction que le chemin FHIR REST — extraite de `appointment.rs` au
//!   moment de ce lot, cf. sa doc de module).
//! - **`SIU^S15`** (annulation) : implémenté, via
//!   [`crate::interop::appointment::update_appointment_status_service`]
//!   vers `cancelled`.
//! - **`SIU^S14`** (modification) : **non implémenté**. Notre modèle
//!   d'écriture actuel (hérité du lot A6) ne permet que des transitions de
//!   *statut* (`PATCH`), pas un changement d'horaire (reschedule) — un vrai
//!   `S14` suppose de modifier `starts_at`/`ends_at`, ce que la couche
//!   service n'expose pas encore. Renvoie une erreur explicite (`AE`,
//!   message clair) plutôt qu'un stub silencieux qui ferait croire à une
//!   prise en compte inexistante — voir [`SiuError::ModifyNotSupported`].
//!
//! ## Résolution patient/praticien — limitation assumée
//!
//! Le matching patient par INS (lot A4) est bloqué sur
//! `crates/core/crypto` (scaffold non implémenté) — hors scope ici. `PID-3`
//! est donc supposé porter directement l'UUID interne Nubia du patient (une
//! répétition avec autorité d'affectation `NUBIA`), et `AIP-3` l'UUID
//! interne du praticien — c'est-à-dire que le partenaire est censé déjà
//! connaître nos identifiants internes (échangés hors-bande, ou via un ADT
//! une fois le lot B8 livré), pas les résoudre par identité clinique. Même
//! limitation que le chemin FHIR REST : `create_appointment_service` ne
//! crée/ne matche jamais un patient, il exige une référence déjà valide.
//!
//! L'annulation (`S15`) résout le rendez-vous cible via `SCH-2` (Filler
//! Appointment ID) traité comme notre UUID interne directement — même
//! logique : le SIH est censé échoer l'identifiant que nous lui avons
//! communiqué (aujourd'hui via l'ACK, pas encore via un identifiant dédié
//! dans la réponse — limitation à revisiter avec la sync sortante, lot A7).

use chrono::{DateTime, NaiveDateTime, Utc};
use integrations_hl7v2::message::{Message, Segment};
use sqlx::PgPool;
use thiserror::Error;
use uuid::Uuid;

use crate::interop::appointment::{
    create_appointment_service, update_appointment_status_service, CreateAppointmentError,
    CreateAppointmentInput, UpdateAppointmentStatusError,
};

/// Erreur de mapping/traitement SIU. `Display` fournit le texte renvoyé en
/// `MSA-3` (ACK `AE`) par `dispatch::process_message` — jamais de détail DB
/// brut, uniquement des messages fail-closed déjà formulés proprement.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum SiuError {
    #[error("segment {0} manquant")]
    MissingSegment(&'static str),
    #[error("champ {0} manquant ou invalide")]
    InvalidField(&'static str),
    #[error("SIU^S14 (modification) non supporté : notre modèle d'écriture ne permet que des transitions de statut, pas un changement d'horaire")]
    ModifyNotSupported,
    #[error("type de message SIU non reconnu : {0}")]
    UnsupportedMessageType(String),
    #[error("création du rendez-vous refusée : {0}")]
    Create(#[from] CreateAppointmentErrorDisplay),
    #[error("mise à jour du rendez-vous refusée : {0}")]
    Update(#[from] UpdateAppointmentStatusErrorDisplay),
}

/// Enveloppe `Display`-able pour [`CreateAppointmentError`] (qui ne
/// dérive pas `Display` lui-même, réservé à un mapping FHIR/`OperationOutcome`
/// côté `appointment.rs`) — évite de dupliquer les messages ici.
#[derive(Debug, PartialEq, Eq)]
pub struct CreateAppointmentErrorDisplay(pub CreateAppointmentError);
impl std::fmt::Display for CreateAppointmentErrorDisplay {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let msg = match &self.0 {
            CreateAppointmentError::PatientNotFound => "patient référencé inconnu de ce cabinet",
            CreateAppointmentError::PractitionerNotFound => {
                "practitioner référencé inconnu de ce cabinet"
            }
            CreateAppointmentError::IdempotencyConflict => {
                "MSH-10 rejoué avec un contenu différent"
            }
            CreateAppointmentError::SlotTaken => "créneau déjà occupé (chevauchement)",
            CreateAppointmentError::Internal => "erreur interne",
        };
        f.write_str(msg)
    }
}
impl From<CreateAppointmentError> for CreateAppointmentErrorDisplay {
    fn from(e: CreateAppointmentError) -> Self {
        Self(e)
    }
}
impl std::error::Error for CreateAppointmentErrorDisplay {}

#[derive(Debug, PartialEq, Eq)]
pub struct UpdateAppointmentStatusErrorDisplay(pub UpdateAppointmentStatusError);
impl std::fmt::Display for UpdateAppointmentStatusErrorDisplay {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match &self.0 {
            UpdateAppointmentStatusError::NotFound => {
                f.write_str("rendez-vous introuvable pour ce cabinet")
            }
            UpdateAppointmentStatusError::IllegalTransition { from, to } => {
                write!(f, "transition '{from}' -> '{to}' non autorisée")
            }
            UpdateAppointmentStatusError::Internal => f.write_str("erreur interne"),
        }
    }
}
impl std::error::Error for UpdateAppointmentStatusErrorDisplay {}
impl From<UpdateAppointmentStatusError> for UpdateAppointmentStatusErrorDisplay {
    fn from(e: UpdateAppointmentStatusError) -> Self {
        Self(e)
    }
}

/// Point d'entrée appelé par `dispatch::process_message` pour tout message
/// du groupe `SIU`. `message_type` est le `MSH-9` complet (ex. `"SIU^S12"`).
pub async fn handle(
    db: &PgPool,
    cabinet_id: Uuid,
    partner_id: Uuid,
    message: &Message,
    message_type: &str,
) -> Result<(), SiuError> {
    let trigger = message_type
        .split('^')
        .nth(1)
        .ok_or_else(|| SiuError::UnsupportedMessageType(message_type.to_string()))?;

    match trigger {
        "S12" => handle_new_appointment(db, cabinet_id, partner_id, message).await,
        "S15" => handle_cancel(db, cabinet_id, message).await,
        "S14" => Err(SiuError::ModifyNotSupported),
        other => Err(SiuError::UnsupportedMessageType(other.to_string())),
    }
}

async fn handle_new_appointment(
    db: &PgPool,
    cabinet_id: Uuid,
    partner_id: Uuid,
    message: &Message,
) -> Result<(), SiuError> {
    let (starts_at, ends_at) = parse_sch_timing(message)?;
    let patient_id = find_internal_patient_id(message)?;
    let practitioner_id = find_internal_practitioner_id(message)?;
    let control_id = msh_control_id(message)?;

    create_appointment_service(
        db,
        cabinet_id,
        partner_id,
        "hl7v2_partner",
        CreateAppointmentInput {
            patient_id,
            practitioner_id,
            starts_at,
            ends_at,
            // Préfixé pour ne jamais collisionner avec une Idempotency-Key
            // FHIR REST (même table `appointment.idempotency_key`).
            idempotency_key: format!("hl7v2:{control_id}"),
        },
    )
    .await
    .map(|_row| ())
    .map_err(|e| SiuError::Create(CreateAppointmentErrorDisplay(e)))
}

async fn handle_cancel(db: &PgPool, cabinet_id: Uuid, message: &Message) -> Result<(), SiuError> {
    let appointment_id = find_filler_appointment_id(message)?;
    update_appointment_status_service(db, cabinet_id, appointment_id, "cancelled")
        .await
        .map(|_row| ())
        .map_err(|e| SiuError::Update(UpdateAppointmentStatusErrorDisplay(e)))
}

// ─────────────────────────────────────────────────────────────────────────
// Extraction des champs HL7 v2 — zéro panique, toujours `Result`.
// ─────────────────────────────────────────────────────────────────────────

fn msh_control_id(message: &Message) -> Result<String, SiuError> {
    message
        .segment("MSH")
        .and_then(|msh| msh.field(10))
        .map(str::to_string)
        .ok_or(SiuError::InvalidField("MSH-10"))
}

/// `SCH-12` : plage horaire, composant 4 = début, composant 5 = fin (format
/// HL7 v2 TS `AAAAMMJJHHMMSS`, UTC assumé — pas de gestion de fuseau
/// explicite dans cette tranche).
fn parse_sch_timing(message: &Message) -> Result<(DateTime<Utc>, DateTime<Utc>), SiuError> {
    let sch = message
        .segment("SCH")
        .ok_or(SiuError::MissingSegment("SCH"))?;
    let start_raw = sch
        .component(12, 4)
        .ok_or(SiuError::InvalidField("SCH-12.4"))?;
    let end_raw = sch
        .component(12, 5)
        .ok_or(SiuError::InvalidField("SCH-12.5"))?;
    let starts_at = parse_hl7_timestamp(start_raw).ok_or(SiuError::InvalidField("SCH-12.4"))?;
    let ends_at = parse_hl7_timestamp(end_raw).ok_or(SiuError::InvalidField("SCH-12.5"))?;
    Ok((starts_at, ends_at))
}

fn parse_hl7_timestamp(raw: &str) -> Option<DateTime<Utc>> {
    NaiveDateTime::parse_from_str(raw, "%Y%m%d%H%M%S")
        .ok()
        .map(|naive| naive.and_utc())
}

/// `SCH-2` (Filler Appointment ID) traité comme notre UUID interne
/// directement — cf. doc de module (limitation assumée).
fn find_filler_appointment_id(message: &Message) -> Result<Uuid, SiuError> {
    let sch = message
        .segment("SCH")
        .ok_or(SiuError::MissingSegment("SCH"))?;
    let raw = sch.field(2).ok_or(SiuError::InvalidField("SCH-2"))?;
    Uuid::parse_str(raw).map_err(|_| SiuError::InvalidField("SCH-2"))
}

/// `PID-3` : liste d'identifiants (répétitions séparées par `~`). Cherche la
/// répétition dont le composant 4 (autorité d'affectation) vaut `NUBIA` et
/// renvoie son composant 1 comme UUID interne — cf. doc de module
/// (limitation assumée, pas de matching INS).
fn find_internal_patient_id(message: &Message) -> Result<Uuid, SiuError> {
    let pid = message
        .segment("PID")
        .ok_or(SiuError::MissingSegment("PID"))?;
    find_nubia_identifier(pid, 3).ok_or(SiuError::InvalidField("PID-3 (identifiant NUBIA)"))
}

/// `AIP-3` (Personnel Resource ID) traité comme notre UUID interne
/// directement (composant 1) — cf. doc de module.
fn find_internal_practitioner_id(message: &Message) -> Result<Uuid, SiuError> {
    let aip = message
        .segment("AIP")
        .ok_or(SiuError::MissingSegment("AIP"))?;
    let raw = aip.component(3, 1).ok_or(SiuError::InvalidField("AIP-3"))?;
    Uuid::parse_str(raw).map_err(|_| SiuError::InvalidField("AIP-3"))
}

/// Cherche, parmi toutes les répétitions du champ `field_n`, celle dont le
/// composant 4 (autorité d'affectation, convention CX de HL7 v2) vaut
/// `NUBIA`, et renvoie son composant 1 parsé en UUID. `None` si aucune
/// répétition ne correspond ou si le composant 1 trouvé n'est pas un UUID
/// valide — jamais de panique sur un champ absent/mal formé.
fn find_nubia_identifier(segment: &Segment, field_n: usize) -> Option<Uuid> {
    let repetitions = segment.repetitions(field_n)?;
    for (idx, _) in repetitions.enumerate() {
        let rep_n = idx + 1;
        if segment.component_in_repetition(field_n, rep_n, 4) == Some("NUBIA") {
            let raw = segment.component_in_repetition(field_n, rep_n, 1)?;
            if let Ok(uuid) = Uuid::parse_str(raw) {
                return Some(uuid);
            }
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use integrations_hl7v2::parser::parse;

    fn siu_s12_message(patient_uuid: &str, practitioner_uuid: &str) -> Message {
        let raw = format!(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260720101500||SIU^S12|CTRL1|P|2.5\r\
             SCH|APPT0001||||||CONSULTATION^Consultation|||30|MIN|^^^20260720090000^20260720093000\r\
             PID|1||{patient_uuid}^^^NUBIA^NI\r\
             AIP|1||{practitioner_uuid}^Dr Martin^L\r"
        );
        parse(&raw).expect("message SIU^S12 de test valide")
    }

    #[test]
    fn parses_sch_timing() {
        let msg = siu_s12_message(&Uuid::new_v4().to_string(), &Uuid::new_v4().to_string());
        let (start, end) = parse_sch_timing(&msg).expect("timing SCH valide");
        assert_eq!(start.to_rfc3339(), "2026-07-20T09:00:00+00:00");
        assert_eq!(end.to_rfc3339(), "2026-07-20T09:30:00+00:00");
    }

    #[test]
    fn finds_internal_patient_id_by_nubia_authority() {
        let patient_id = Uuid::new_v4();
        let msg = siu_s12_message(&patient_id.to_string(), &Uuid::new_v4().to_string());
        assert_eq!(find_internal_patient_id(&msg), Ok(patient_id));
    }

    #[test]
    fn finds_internal_practitioner_id_from_aip() {
        let practitioner_id = Uuid::new_v4();
        let msg = siu_s12_message(&Uuid::new_v4().to_string(), &practitioner_id.to_string());
        assert_eq!(find_internal_practitioner_id(&msg), Ok(practitioner_id));
    }

    #[test]
    fn missing_pid_segment_is_missing_segment_error() {
        let msg = parse(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260720101500||SIU^S12|CTRL1|P|2.5\r\
             SCH|APPT0001||||||CONSULTATION^Consultation|||30|MIN|^^^20260720090000^20260720093000\r",
        )
        .unwrap();
        assert_eq!(
            find_internal_patient_id(&msg),
            Err(SiuError::MissingSegment("PID"))
        );
    }

    #[test]
    fn pid_without_nubia_authority_is_invalid_field() {
        let msg = parse(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260720101500||SIU^S12|CTRL1|P|2.5\r\
             PID|1||123456^^^HOPITAL1^PI\r",
        )
        .unwrap();
        assert_eq!(
            find_internal_patient_id(&msg),
            Err(SiuError::InvalidField("PID-3 (identifiant NUBIA)"))
        );
    }

    #[test]
    fn filler_appointment_id_parses_sch_2_as_uuid() {
        let appt_id = Uuid::new_v4();
        let raw = format!(
            "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260720101500||SIU^S15|CTRL2|P|2.5\r\
             SCH|APPT0001|{appt_id}\r"
        );
        let msg = parse(&raw).unwrap();
        assert_eq!(find_filler_appointment_id(&msg), Ok(appt_id));
    }

    #[tokio::test]
    async fn s14_is_explicitly_not_supported() {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://fake@localhost/fake")
            .unwrap();
        let msg = siu_s12_message(&Uuid::new_v4().to_string(), &Uuid::new_v4().to_string());
        let result = handle(&pool, Uuid::new_v4(), Uuid::new_v4(), &msg, "SIU^S14").await;
        assert_eq!(result, Err(SiuError::ModifyNotSupported));
    }

    #[tokio::test]
    async fn unknown_siu_trigger_is_unsupported_message_type() {
        let pool = sqlx::postgres::PgPoolOptions::new()
            .connect_lazy("postgres://fake@localhost/fake")
            .unwrap();
        let msg = siu_s12_message(&Uuid::new_v4().to_string(), &Uuid::new_v4().to_string());
        let result = handle(&pool, Uuid::new_v4(), Uuid::new_v4(), &msg, "SIU^S99").await;
        assert_eq!(
            result,
            Err(SiuError::UnsupportedMessageType("S99".to_string()))
        );
    }
}
