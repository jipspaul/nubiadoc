//! Parseur HL7 v2 "à la main" (grammaire à délimiteurs) : jamais de panique,
//! même sur un message tronqué, malformé, ou contenant des octets arbitraires.
//!
//! Grammaire : segments séparés par `\r` (0x0D) ; dans un segment, champs
//! séparés par `|`, composants par `^`, sous-composants par `&`, répétitions
//! par `~`, échappement par `\`. Le séparateur de champ est toujours `|`
//! (MSH-1) ; les quatre autres caractères sont déclarés dynamiquement en
//! MSH-2 et peuvent en théorie différer du jeu par défaut (rare en pratique,
//! mais géré ici).

use thiserror::Error;

use crate::message::{EncodingChars, Message, Segment};

/// Séparateur de champ HL7 v2 (MSH-1). Toujours `|` : contrairement aux
/// quatre autres caractères d'encodage, ce n'est pas un choix laissé au
/// message (la norme le fixe, et il sert justement à délimiter MSH-2 qui,
/// lui, contient les caractères variables).
const FIELD_SEP: char = '|';

/// Erreur de parsing HL7 v2. Un message malformé ou tronqué produit toujours
/// une variante de cette erreur, jamais une panique.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum Hl7Error {
    /// Le message ne commence pas par un segment `MSH`, ou est vide.
    #[error("segment MSH manquant : le message doit commencer par un segment MSH")]
    MissingMsh,
    /// MSH-2 (caractères d'encodage) est absent, tronqué, ou mal délimité.
    #[error("caractères d'encodage MSH-2 invalides ou tronqués")]
    InvalidEncodingChars,
    /// Un segment, une fois découpé, fait moins de 3 caractères et ne peut
    /// donc pas porter d'identifiant de segment valide.
    #[error("segment vide ou trop court pour contenir un identifiant de 3 caractères")]
    EmptySegment,
    /// Le message est vide ou ne contient aucun segment exploitable.
    #[error("message tronqué : aucun contenu à parser")]
    TruncatedMessage,
    /// Les octets fournis ne sont pas de l'UTF-8 valide (voir [`parse_bytes`]).
    #[error("contenu non-UTF8 : {0}")]
    InvalidUtf8(#[from] std::str::Utf8Error),
}

/// Parse un message HL7 v2 à partir d'une chaîne UTF-8.
///
/// Ne panique jamais : tout message malformé ou tronqué produit un
/// `Err(Hl7Error)`.
pub fn parse(input: &str) -> Result<Message, Hl7Error> {
    let raw_segments = split_segments(input);
    let msh_raw: &str = raw_segments
        .first()
        .copied()
        .ok_or(Hl7Error::TruncatedMessage)?;
    if !msh_raw.starts_with("MSH") {
        return Err(Hl7Error::MissingMsh);
    }
    let (encoding, _) = parse_msh_header(msh_raw)?;

    let mut segments = Vec::with_capacity(raw_segments.len());
    for raw in &raw_segments {
        segments.push(parse_segment(raw, encoding)?);
    }
    Ok(Message::new(segments))
}

/// Parse un message HL7 v2 à partir d'octets bruts (ex: sortie d'un lecteur
/// de trame MLLP). Convenience wrapper autour de [`parse`] : valide l'UTF-8
/// d'abord (`Hl7Error::InvalidUtf8` si invalide), jamais de panique sur des
/// octets arbitraires/aléatoires.
pub fn parse_bytes(input: &[u8]) -> Result<Message, Hl7Error> {
    let s = std::str::from_utf8(input)?;
    parse(s)
}

/// Découpe le message en segments bruts sur `\r` ou `\n` (tolère aussi les
/// fins de ligne `\r\n` mal formées par certains émetteurs), en filtrant les
/// segments vides issus d'un terminateur final ou d'un `\r\n`.
fn split_segments(input: &str) -> Vec<&str> {
    input
        .split(['\r', '\n'])
        .filter(|s| !s.is_empty())
        .collect()
}

/// Extrait les caractères d'encodage depuis le segment MSH brut, et renvoie
/// aussi l'offset (en octets, sur une frontière de caractère valide) à partir
/// duquel commencent les champs MSH-3 et suivants.
///
/// Sûr sur toute entrée arbitraire : n'utilise que `char_indices`/longueurs
/// de caractères pour calculer les offsets, jamais d'indexation fixe par
/// octet — un message tronqué ou contenant des caractères multi-octets ne
/// peut donc pas déclencher de panique de découpage de chaîne.
fn parse_msh_header(raw: &str) -> Result<(EncodingChars, usize), Hl7Error> {
    let rest = raw.strip_prefix("MSH").ok_or(Hl7Error::MissingMsh)?;
    let mut chars = rest.char_indices();

    let (sep1_idx, sep1_ch) = chars.next().ok_or(Hl7Error::InvalidEncodingChars)?;
    if sep1_ch != FIELD_SEP {
        return Err(Hl7Error::InvalidEncodingChars);
    }
    let _ = sep1_idx;

    // Les 4 caractères suivants sont MSH-2 : composant, répétition,
    // échappement, sous-composant (dans cet ordre, ex: `^~\&`).
    let mut enc_chars: Vec<char> = Vec::with_capacity(4);
    for _ in 0..4 {
        let (_, c) = chars.next().ok_or(Hl7Error::InvalidEncodingChars)?;
        enc_chars.push(c);
    }
    let component = enc_chars[0];
    let repetition = enc_chars[1];
    let escape = enc_chars[2];
    let subcomponent = enc_chars[3];

    // Le caractère suivant doit être à nouveau le séparateur de champ,
    // marquant le début de MSH-3.
    let (sep2_idx, sep2_ch) = chars.next().ok_or(Hl7Error::InvalidEncodingChars)?;
    if sep2_ch != FIELD_SEP {
        return Err(Hl7Error::InvalidEncodingChars);
    }

    let encoding = EncodingChars {
        component,
        repetition,
        escape,
        subcomponent,
    };
    // Offset (dans `raw`) du premier octet suivant ce second séparateur :
    // "MSH" fait toujours 3 octets ASCII, et sep2_idx/sep2_ch sont calculés
    // relativement à `rest`, donc toujours sur une frontière de caractère
    // valide de `raw`.
    let rest_start = "MSH".len() + sep2_idx + sep2_ch.len_utf8();
    Ok((encoding, rest_start))
}

/// Parse un segment brut (après découpage sur `\r`/`\n`) en [`Segment`].
/// `encoding` doit avoir été extrait au préalable du segment MSH du message.
fn parse_segment(raw: &str, encoding: EncodingChars) -> Result<Segment, Hl7Error> {
    // Calcule, sans jamais indexer par octet fixe, la frontière de caractère
    // juste après les 3 premiers caractères (identifiant de segment).
    let mut iter = raw.char_indices();
    let mut count = 0usize;
    let mut id_end = 0usize;
    for (idx, ch) in &mut iter {
        count += 1;
        id_end = idx + ch.len_utf8();
        if count == 3 {
            break;
        }
    }
    if count < 3 {
        return Err(Hl7Error::EmptySegment);
    }

    let id = raw[..id_end].to_string();
    if id == "MSH" {
        return parse_msh_segment(raw);
    }

    let rest = &raw[id_end..];
    let fields: Vec<String> = if rest.is_empty() {
        Vec::new()
    } else {
        let content = rest.strip_prefix(FIELD_SEP).unwrap_or(rest);
        content.split(FIELD_SEP).map(str::to_string).collect()
    };
    Ok(Segment::new(id, fields, encoding))
}

/// Parse spécifiquement le segment MSH : field(1) vaut conventionnellement le
/// séparateur de champ lui-même, field(2) la chaîne des caractères
/// d'encodage, et les champs suivants sont ceux découpés après MSH-2.
fn parse_msh_segment(raw: &str) -> Result<Segment, Hl7Error> {
    let (encoding, rest_start) = parse_msh_header(raw)?;

    let mut fields = Vec::new();
    fields.push(FIELD_SEP.to_string()); // MSH-1 : le séparateur de champ lui-même.
    let enc_str: String = [
        encoding.component,
        encoding.repetition,
        encoding.escape,
        encoding.subcomponent,
    ]
    .into_iter()
    .collect();
    fields.push(enc_str); // MSH-2 : les 4 caractères d'encodage.

    let rest = &raw[rest_start..];
    if !rest.is_empty() {
        fields.extend(rest.split(FIELD_SEP).map(str::to_string));
    }

    Ok(Segment::new("MSH".to_string(), fields, encoding))
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Message ADT^A28 (création de patient) couvrant tous les champs MSH et
    /// PID documentés dans le brief, plus un PV1 minimal pour vérifier que sa
    /// présence ne casse pas le parsing générique.
    const ADT_A28: &str =
        "MSH|^~\\&|NUBIA|CABINET1|SIH|HOPITAL1|20260719101500||ADT^A28|MSGID0001|P|2.5\r\
PID|1||123456^^^HOPITAL1^PI~2600112233044^^^INS-NIR^NI||DUPONT^JEAN||19800101|M\r\
PV1|1|O\r";

    /// Message SIU^S12 (création de rendez-vous) couvrant SCH + les segments
    /// de ressources AIS/AIL/AIP, encore une fois pour valider qu'ils ne
    /// cassent pas le parsing générique (pas de struct dédiée : le Segment
    /// générique suffit à les exposer).
    const SIU_S12: &str =
        "MSH|^~\\&|SIH|HOPITAL1|NUBIA|CABINET1|20260719101500||SIU^S12|MSGID0002|P|2.5\r\
SCH|APPT0001||||||CONSULTATION^Consultation generaliste|||30|MIN|^^^20260720090000^20260720093000\r\
PID|1||123456^^^HOPITAL1^PI||DUPONT^JEAN||19800101|M\r\
PV1|1|O\r\
AIS|1||CONSULTATION\r\
AIL|1||CABINET1^^^HOPITAL1\r\
AIP|1||DRMARTIN^MARTIN^JEAN\r";

    #[test]
    fn adt_a28_parses_and_all_documented_fields_are_retrievable() {
        let msg = parse(ADT_A28).expect("message ADT^A28 valide doit parser");

        let msh = msg.segment("MSH").expect("MSH doit être présent");
        assert_eq!(msh.field(1), Some("|"));
        assert_eq!(msh.field(2), Some("^~\\&"));
        assert_eq!(msh.field(4), Some("CABINET1")); // sending facility
        assert_eq!(msh.field(6), Some("HOPITAL1")); // receiving facility
        assert_eq!(msh.field(9), Some("ADT^A28"));
        assert_eq!(msh.component(9, 1), Some("ADT"));
        assert_eq!(msh.component(9, 2), Some("A28"));
        assert_eq!(msh.field(10), Some("MSGID0001")); // message control id
        assert_eq!(msh.field(11), Some("P")); // processing id

        let pid = msg.segment("PID").expect("PID doit être présent");
        // PID-3 : liste d'identifiants répétés, incluant un INS-NIR avec son
        // autorité d'affectation en composant 4 de la 2e répétition.
        assert_eq!(pid.component_in_repetition(3, 1, 1), Some("123456"));
        assert_eq!(pid.component_in_repetition(3, 1, 4), Some("HOPITAL1"));
        assert_eq!(pid.component_in_repetition(3, 2, 1), Some("2600112233044"));
        assert_eq!(pid.component_in_repetition(3, 2, 4), Some("INS-NIR"));
        assert_eq!(pid.component_in_repetition(3, 2, 5), Some("NI"));
        let reps: Vec<&str> = pid.repetitions(3).expect("PID-3 doit exister").collect();
        assert_eq!(reps.len(), 2);
        // PID-5 : nom.
        assert_eq!(pid.component(5, 1), Some("DUPONT"));
        assert_eq!(pid.component(5, 2), Some("JEAN"));
        // PID-7 : date de naissance.
        assert_eq!(pid.field(7), Some("19800101"));
        // PID-8 : sexe.
        assert_eq!(pid.field(8), Some("M"));

        // PV1 présent, ne casse pas le parsing, accessible génériquement.
        let pv1 = msg.segment("PV1").expect("PV1 doit être présent");
        assert_eq!(pv1.field(2), Some("O"));
    }

    #[test]
    fn siu_s12_parses_with_sch_and_resource_segments() {
        let msg = parse(SIU_S12).expect("message SIU^S12 valide doit parser");

        let msh = msg.segment("MSH").expect("MSH doit être présent");
        assert_eq!(msh.field(9), Some("SIU^S12"));

        let sch = msg.segment("SCH").expect("SCH doit être présent");
        assert_eq!(sch.field(1), Some("APPT0001"));
        assert_eq!(sch.field(11), Some("MIN"));
        // SCH-12 : plage horaire, composant 4 = début.
        assert_eq!(sch.component(12, 4), Some("20260720090000"));
        assert_eq!(sch.component(12, 5), Some("20260720093000"));

        assert!(msg.segment("AIS").is_some());
        assert!(msg.segment("AIL").is_some());
        assert!(msg.segment("AIP").is_some());
        assert_eq!(
            msg.segment("AIP").unwrap().component(3, 1),
            Some("DRMARTIN")
        );
    }

    #[test]
    fn missing_msh_segment_is_an_error() {
        let input = "PID|1||123456\r";
        assert_eq!(parse(input), Err(Hl7Error::MissingMsh));
    }

    #[test]
    fn empty_input_is_truncated_message() {
        assert_eq!(parse(""), Err(Hl7Error::TruncatedMessage));
        // Uniquement des terminateurs, aucun contenu exploitable.
        assert_eq!(parse("\r\r\r"), Err(Hl7Error::TruncatedMessage));
    }

    #[test]
    fn truncated_msh_header_is_invalid_encoding_chars() {
        assert_eq!(parse("MSH"), Err(Hl7Error::InvalidEncodingChars));
        assert_eq!(parse("MSH|^~"), Err(Hl7Error::InvalidEncodingChars));
        // Le caractère attendu après les 4 chars d'encodage n'est pas le
        // séparateur de champ : header invalide.
        assert_eq!(parse("MSH|^~\\&X"), Err(Hl7Error::InvalidEncodingChars));
    }

    #[test]
    fn segment_shorter_than_three_chars_is_empty_segment_error() {
        // "XX" ne fait que 2 caractères : impossible d'en extraire un
        // identifiant de segment valide.
        let input = "MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\rXX\r";
        assert_eq!(parse(input), Err(Hl7Error::EmptySegment));
    }

    #[test]
    fn garbage_bytes_never_panic_and_produce_an_error() {
        // Octets non-UTF8 : doivent produire une erreur via parse_bytes, pas
        // de panique.
        let garbage: &[u8] = &[0xFF, 0xFE, 0x00, 0x01, 0x0D];
        assert!(matches!(
            parse_bytes(garbage),
            Err(Hl7Error::InvalidUtf8(_))
        ));

        // Contenu UTF-8 valide mais sans MSH : erreur normale, pas de panique.
        let no_msh = "é😀\rXY\r";
        assert!(parse(no_msh).is_err());

        // Segment multi-octets trop court après un MSH valide : le comptage
        // de caractères (pas d'octets) doit détecter l'EmptySegment sans
        // jamais découper une chaîne sur une frontière d'octet invalide.
        let short_multibyte_segment = "MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\rZ😀\r";
        assert_eq!(parse(short_multibyte_segment), Err(Hl7Error::EmptySegment));

        // Segment dont l'identifiant lui-même contient des caractères
        // multi-octets (3 caractères, donc valide en nombre de caractères
        // même si ce n'est pas ASCII) : ne doit jamais paniquer au découpage.
        let multibyte_segment_id = "MSH|^~\\&|A|B|C|D|20260719||ADT^A28|1|P|2.5\r😀😀😀|X\r";
        let msg = parse(multibyte_segment_id).expect("segment id multi-octets valide doit parser");
        assert_eq!(msg.segment("😀😀😀").and_then(|s| s.field(1)), Some("X"));
    }

    #[test]
    fn field_and_component_index_past_end_is_none_not_panic() {
        let msg = parse(ADT_A28).expect("message valide doit parser");
        let pid = msg.segment("PID").expect("PID doit être présent");
        assert_eq!(pid.field(0), None);
        assert_eq!(pid.field(999), None);
        assert_eq!(pid.component(3, 999), None);
        assert_eq!(pid.component(999, 1), None);
        assert_eq!(pid.subcomponent(3, 1, 999), None);
        assert_eq!(msg.segment("ZZZ"), None);
    }

    #[test]
    fn non_default_encoding_characters_are_supported() {
        // MSH-2 déclare des caractères d'encodage non standards :
        // composant='@', répétition='#', échappement='$', sous-composant='*'.
        let input = "MSH|@#$*|SENDER|FAC1|RECV|FAC2|20260719||ADT@A28|CTRL1|P|2.5\r\
PID|1||ID1@ID2@@AUTH@TYPE|\r";
        let msg = parse(input).expect("encodage non standard doit parser");

        let msh = msg.segment("MSH").expect("MSH présent");
        assert_eq!(msh.field(2), Some("@#$*"));
        assert_eq!(msh.component(9, 1), Some("ADT"));
        assert_eq!(msh.component(9, 2), Some("A28"));

        let pid = msg.segment("PID").expect("PID présent");
        assert_eq!(pid.component(3, 1), Some("ID1"));
        assert_eq!(pid.component(3, 2), Some("ID2"));
        assert_eq!(pid.component(3, 4), Some("AUTH"));
    }
}
