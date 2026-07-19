//! Génération d'un accusé de réception (ACK) HL7 v2 : un segment `MSH` + un
//! segment `MSA`, tel qu'exigé par la norme pour chaque message reçu.
//!
//! Cette crate reste pure et testable : elle ne génère ni ID de contrôle
//! aléatoire ni horodatage. L'ID de contrôle du message ACK ([`AckParams::ack_control_id`])
//! doit être fourni par l'appelant (horodatage/UUID, etc.) — c'est un lot
//! ultérieur (dispatch/service layer) qui en aura la responsabilité.

/// Code d'issue applicatif HL7 v2 à placer en MSA-1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AckCode {
    /// `AA` — Application Accept : message reçu et traité avec succès.
    ApplicationAccept,
    /// `AE` — Application Error : erreur applicative lors du traitement.
    ApplicationError,
    /// `AR` — Application Reject : message rejeté (non traité).
    ApplicationReject,
}

impl AckCode {
    fn as_hl7(self) -> &'static str {
        match self {
            AckCode::ApplicationAccept => "AA",
            AckCode::ApplicationError => "AE",
            AckCode::ApplicationReject => "AR",
        }
    }
}

/// Paramètres de construction d'un message ACK.
#[derive(Debug, Clone, Copy)]
pub struct AckParams<'a> {
    /// MSH-10 du message original : échoué dans MSA-2.
    pub original_control_id: &'a str,
    /// MSH-10 du message ACK lui-même. Généré par l'appelant (cette crate ne
    /// génère ni horodatage ni aléa) : voir la documentation du module.
    pub ack_control_id: &'a str,
    /// Code d'issue placé en MSA-1.
    pub code: AckCode,
    /// Texte optionnel placé en MSA-3, utile pour expliquer un `AE`/`AR`.
    pub text: Option<&'a str>,
}

/// Construit les octets (segments joints par `\r`, `\r` final inclus) d'un
/// message ACK minimal valide : un segment `MSH` (encodage par défaut
/// `^~\&`, type de message `ACK`, version `2.5`) suivi d'un segment `MSA`.
pub fn build_ack(params: &AckParams<'_>) -> String {
    let msh_fields = [
        "^~\\&",               // MSH-2 : caractères d'encodage par défaut.
        "",                    // MSH-3 : application émettrice — non renseignée ici.
        "",                    // MSH-4 : établissement émetteur — non renseigné ici.
        "",                    // MSH-5 : application destinataire — non renseignée ici.
        "",                    // MSH-6 : établissement destinataire — non renseigné ici.
        "",                    // MSH-7 : date/heure — à la charge de l'appelant si besoin.
        "",                    // MSH-8 : sécurité — non utilisée.
        "ACK",                 // MSH-9 : type de message.
        params.ack_control_id, // MSH-10 : ID de contrôle du message ACK.
        "P",                   // MSH-11 : ID de traitement (Production).
        "2.5",                 // MSH-12 : version HL7.
    ];
    let msh = format!("MSH|{}", msh_fields.join("|"));

    let msa_fields = [
        params.code.as_hl7(),
        params.original_control_id,
        params.text.unwrap_or(""),
    ];
    let msa = format!("MSA|{}", msa_fields.join("|"));

    format!("{msh}\r{msa}\r")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::parse;

    #[test]
    fn aa_ack_round_trips_through_parser_and_echoes_control_id() {
        let params = AckParams {
            original_control_id: "MSGID0001",
            ack_control_id: "ACKID0001",
            code: AckCode::ApplicationAccept,
            text: None,
        };
        let raw = build_ack(&params);
        let msg = parse(&raw).expect("ACK généré doit se re-parser");

        let msh = msg.segment("MSH").expect("MSH doit être présent");
        assert_eq!(msh.field(9), Some("ACK"));
        assert_eq!(msh.field(10), Some("ACKID0001"));

        let msa = msg.segment("MSA").expect("MSA doit être présent");
        assert_eq!(msa.field(1), Some("AA"));
        assert_eq!(msa.field(2), Some("MSGID0001"));
    }

    #[test]
    fn ae_ack_round_trips_with_text() {
        let params = AckParams {
            original_control_id: "MSGID0002",
            ack_control_id: "ACKID0002",
            code: AckCode::ApplicationError,
            text: Some("patient introuvable"),
        };
        let raw = build_ack(&params);
        let msg = parse(&raw).expect("ACK généré doit se re-parser");

        let msa = msg.segment("MSA").expect("MSA doit être présent");
        assert_eq!(msa.field(1), Some("AE"));
        assert_eq!(msa.field(2), Some("MSGID0002"));
        assert_eq!(msa.field(3), Some("patient introuvable"));
    }

    #[test]
    fn ar_ack_round_trips_and_echoes_control_id() {
        let params = AckParams {
            original_control_id: "MSGID0003",
            ack_control_id: "ACKID0003",
            code: AckCode::ApplicationReject,
            text: Some("format non supporté"),
        };
        let raw = build_ack(&params);
        let msg = parse(&raw).expect("ACK généré doit se re-parser");

        let msa = msg.segment("MSA").expect("MSA doit être présent");
        assert_eq!(msa.field(1), Some("AR"));
        assert_eq!(msa.field(2), Some("MSGID0003"));
        assert_eq!(msa.field(3), Some("format non supporté"));
    }
}
