//! Rendu de modèles `.docx` pour le moteur de courriers (#7157, suite de
//! #7197) : import d'un fichier `.docx` (OOXML, archive zip) contenant des
//! placeholders `{{ns.champ}}`, extraction de la liste, substitution
//! directement dans `word/document.xml` (seul flux XML qui porte le corps
//! d'un `.docx` simple, sans en-tête/pied-de-page dédiés).
//!
//! Le fichier n'est jamais parsé comme un XML structuré : les placeholders
//! et le texte des runs (`<w:t>...</w:t>`) sont repérés par recherche de
//! sous-chaînes, comme `letters::render` pour le texte libre — suffisant
//! puisqu'on ne modifie jamais la structure des balises, seulement le
//! contenu textuel.
//!
//! Limite connue et volontaire : un placeholder que Word scinde entre deux
//! runs de formatage différents (l'utilisateur a mis en gras la moitié du
//! texte, l'autocorrection a inséré une balise au milieu de `{{...}}`…)
//! contient alors une balise XML entre les accolades — il n'est ni détecté
//! au listing, ni substitué au rendu (laissé tel quel, littéral). Seul le
//! cas usuel (placeholder saisi d'un seul tenant dans un même run) est
//! supporté.
//!
//! Conversion PDF : [`try_convert_to_pdf`] est *best-effort* via `soffice`
//! (LibreOffice) s'il est présent sur le système d'exécution — absent en
//! CI/dev, le rendu reste alors un `.docx` (cf. `letters::
//! generate_patient_letter`), conformément à l'issue (« conversion PDF si
//! un convertisseur est disponible, sinon DOCX rendu »).

use std::collections::BTreeMap;
use std::io::{Cursor, Read, Write};

use zip::{write::FileOptions, ZipArchive, ZipWriter};

use crate::auth::AppError;
use crate::letters::KNOWN_PLACEHOLDERS;

/// MIME OOXML WordprocessingML — déclaré par le client à l'import et utilisé
/// comme `document.mime_type` quand le rendu reste un `.docx` (pas de
/// convertisseur PDF disponible).
pub(crate) const DOCX_MIME: &str =
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document";

const DOCUMENT_XML_PATH: &str = "word/document.xml";

/// Taille maximale du `word/document.xml` **décompressé** (#7524) —
/// `letters::MAX_DOCX_UPLOAD_SIZE` ne borne que l'archive `.docx` reçue
/// (compressée) ; un contenu très répétitif (paragraphes dupliqués) peut
/// décompresser à un multiple de cette taille sans jamais dépasser le
/// plafond d'upload. Même ordre de grandeur que `MAX_DOCX_UPLOAD_SIZE` :
/// c'est le même garde-fou mémoire, appliqué à ce qui est réellement chargé
/// en mémoire (le flux inflaté, lu par `read_document_xml`).
const MAX_DOCUMENT_XML_SIZE: usize = 5 * 1024 * 1024;

/// Erreur du moteur `.docx`, convertie en `AppError` par les handlers
/// (même mapping que `letters::RenderError`).
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum DocxError {
    /// Zip invalide ou `word/document.xml` absent : ce n'est pas un `.docx`.
    NotADocx,
    /// `word/document.xml` décompressé dépasse `MAX_DOCUMENT_XML_SIZE`
    /// (#7524) — rejeté avant que la substitution/l'aperçu n'en fassent
    /// chacun une copie complète en mémoire.
    TooLarge,
    /// `{{` sans `}}` fermant dans `word/document.xml`.
    Malformed,
    /// Placeholders hors `KNOWN_PLACEHOLDERS` (dédoublonnés, ordre d'apparition).
    Unknown(Vec<String>),
    /// Placeholders connus mais sans valeur dans le contexte (idem).
    Missing(Vec<String>),
}

impl From<DocxError> for AppError {
    fn from(err: DocxError) -> Self {
        match err {
            DocxError::NotADocx | DocxError::TooLarge | DocxError::Malformed => {
                AppError::ValidationError
            }
            DocxError::Unknown(list) => AppError::UnknownPlaceholders(list),
            DocxError::Missing(list) => AppError::MissingPlaceholderValues(list),
        }
    }
}

fn push_unique(list: &mut Vec<String>, name: &str) {
    if !list.iter().any(|n| n == name) {
        list.push(name.to_string());
    }
}

/// Un segment de `word/document.xml` une fois analysé.
#[derive(Debug, PartialEq, Eq)]
enum Segment<'a> {
    Text(&'a str),
    Placeholder(String),
    /// `{{...}}` scindé par une balise (run coupé) — texte littéral, jamais
    /// substitué (cf. limite documentée en tête de module).
    Verbatim(&'a str),
}

/// Découpe `xml` en segments texte / placeholder / verbatim. Un `{{` non
/// fermé → [`DocxError::Malformed`].
fn parse(xml: &str) -> Result<Vec<Segment<'_>>, DocxError> {
    let mut segments = Vec::new();
    let mut rest = xml;
    while let Some(start) = rest.find("{{") {
        if start > 0 {
            segments.push(Segment::Text(&rest[..start]));
        }
        let after = &rest[start + 2..];
        let Some(end) = after.find("}}") else {
            return Err(DocxError::Malformed);
        };
        let raw = &after[..end];
        if raw.contains('<') || raw.contains('>') {
            segments.push(Segment::Verbatim(&rest[start..start + 2 + end + 2]));
        } else {
            segments.push(Segment::Placeholder(raw.trim().to_string()));
        }
        rest = &after[end + 2..];
    }
    if !rest.is_empty() {
        segments.push(Segment::Text(rest));
    }
    Ok(segments)
}

/// Lit `word/document.xml` d'un `.docx` (archive zip OOXML).
fn read_document_xml(bytes: &[u8]) -> Result<String, DocxError> {
    let mut archive = ZipArchive::new(Cursor::new(bytes)).map_err(|_| DocxError::NotADocx)?;
    let file = archive
        .by_name(DOCUMENT_XML_PATH)
        .map_err(|_| DocxError::NotADocx)?;
    // `take(N + 1)` borne l'inflation réelle (le flux n'est décompressé
    // qu'au fil de la lecture) : un document.xml plus grand que la limite
    // s'arrête après N+1 octets lus plutôt que d'être entièrement
    // décompressé en mémoire avant d'être rejeté (#7524).
    let mut limited = file.take(MAX_DOCUMENT_XML_SIZE as u64 + 1);
    let mut xml = String::new();
    limited
        .read_to_string(&mut xml)
        .map_err(|_| DocxError::NotADocx)?;
    if xml.len() > MAX_DOCUMENT_XML_SIZE {
        return Err(DocxError::TooLarge);
    }
    Ok(xml)
}

/// Placeholders utilisés par un modèle `.docx` (`KNOWN_PLACEHOLDERS`
/// uniquement), dédoublonnés, dans l'ordre d'apparition. Erreur si le
/// fichier n'est pas un `.docx` valide, si `word/document.xml` contient un
/// `{{` non fermé, ou référence un placeholder inconnu.
pub(crate) fn placeholders(bytes: &[u8]) -> Result<Vec<String>, DocxError> {
    let xml = read_document_xml(bytes)?;
    let mut used = Vec::new();
    let mut unknown = Vec::new();
    for segment in parse(&xml)? {
        if let Segment::Placeholder(name) = segment {
            if KNOWN_PLACEHOLDERS.contains(&name.as_str()) {
                push_unique(&mut used, &name);
            } else {
                push_unique(&mut unknown, &name);
            }
        }
    }
    if !unknown.is_empty() {
        return Err(DocxError::Unknown(unknown));
    }
    Ok(used)
}

/// Échappe une valeur pour insertion dans le texte d'un `<w:t>`.
fn escape_xml(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

/// Défait l'échappement XML — utilisé uniquement par [`extract_text`] (la
/// prévisualisation, jamais la substitution elle-même).
fn unescape_xml(value: &str) -> String {
    value
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&apos;", "'")
        .replace("&quot;", "\"")
        .replace("&amp;", "&")
}

/// Substitue les placeholders connus de `xml` par `values` — même contrat
/// que `letters::render` (erreurs `Unknown`/`Missing`), mais opère
/// directement sur le XML brut du document.
fn substitute(xml: &str, values: &BTreeMap<String, String>) -> Result<String, DocxError> {
    let segments = parse(xml)?;
    let mut unknown = Vec::new();
    let mut missing = Vec::new();
    let mut out = String::with_capacity(xml.len());
    for segment in &segments {
        match segment {
            Segment::Text(text) => out.push_str(text),
            Segment::Verbatim(raw) => out.push_str(raw),
            Segment::Placeholder(name) => {
                if !KNOWN_PLACEHOLDERS.contains(&name.as_str()) {
                    push_unique(&mut unknown, name);
                } else if let Some(value) = values.get(name) {
                    out.push_str(&escape_xml(value));
                } else {
                    push_unique(&mut missing, name);
                }
            }
        }
    }
    if !unknown.is_empty() {
        return Err(DocxError::Unknown(unknown));
    }
    if !missing.is_empty() {
        return Err(DocxError::Missing(missing));
    }
    Ok(out)
}

/// Réécrit `original` en remplaçant `word/document.xml` par `new_xml` — le
/// reste de l'archive (styles, médias, rels…) est recopié tel quel via
/// `raw_copy_file` (pas de recompression).
fn rewrite_document_xml(original: &[u8], new_xml: &str) -> Result<Vec<u8>, DocxError> {
    let mut archive = ZipArchive::new(Cursor::new(original)).map_err(|_| DocxError::NotADocx)?;
    let mut out_buf = Vec::new();
    {
        let mut writer = ZipWriter::new(Cursor::new(&mut out_buf));
        for i in 0..archive.len() {
            let file = archive.by_index(i).map_err(|_| DocxError::NotADocx)?;
            let name = file.name().to_string();
            if name == DOCUMENT_XML_PATH {
                let options = FileOptions::default().compression_method(file.compression());
                drop(file);
                writer
                    .start_file(name, options)
                    .map_err(|_| DocxError::NotADocx)?;
                writer
                    .write_all(new_xml.as_bytes())
                    .map_err(|_| DocxError::NotADocx)?;
            } else {
                writer
                    .raw_copy_file(file)
                    .map_err(|_| DocxError::NotADocx)?;
            }
        }
        writer.finish().map_err(|_| DocxError::NotADocx)?;
    }
    Ok(out_buf)
}

/// Rend un modèle `.docx` par substitution dans `word/document.xml`. Le
/// reste de l'archive (styles, médias…) est préservé à l'identique.
pub(crate) fn render(
    bytes: &[u8],
    values: &BTreeMap<String, String>,
) -> Result<Vec<u8>, DocxError> {
    let xml = read_document_xml(bytes)?;
    let rendered_xml = substitute(&xml, values)?;
    rewrite_document_xml(bytes, &rendered_xml)
}

/// Avance `rest` d'un run `<w:t>...</w:t>` (ou `<w:t/>` auto-fermant),
/// poussant son contenu dans `out` — utilisé par [`extract_text`].
fn extract_run<'a>(rest: &'a str, t_pos: usize, out: &mut String) -> &'a str {
    let after_tag_start = &rest[t_pos..];
    let Some(open_end) = after_tag_start.find('>') else {
        return "";
    };
    let tag = &after_tag_start[..open_end];
    let after_open = &after_tag_start[open_end + 1..];
    if tag.ends_with('/') {
        return after_open;
    }
    let Some(close) = after_open.find("</w:t>") else {
        return "";
    };
    out.push_str(&unescape_xml(&after_open[..close]));
    &after_open[close + "</w:t>".len()..]
}

/// Texte brut best-effort d'un `.docx` rendu (concatène les `<w:t>`, saut de
/// ligne à chaque `</w:p>`) — prévisualisation uniquement
/// (`GenerateLetterResponse.body`), jamais utilisé pour la substitution.
/// Chaîne vide si `bytes` n'est pas un `.docx` lisible.
pub(crate) fn extract_text(bytes: &[u8]) -> String {
    let xml = match read_document_xml(bytes) {
        Ok(xml) => xml,
        Err(_) => return String::new(),
    };
    let mut out = String::new();
    let mut rest = xml.as_str();
    loop {
        let t_pos = rest.find("<w:t");
        let p_pos = rest.find("</w:p>");
        match (t_pos, p_pos) {
            (Some(t), Some(p)) if t < p => rest = extract_run(rest, t, &mut out),
            (Some(t), None) => rest = extract_run(rest, t, &mut out),
            (_, Some(p)) => {
                out.push('\n');
                rest = &rest[p + "</w:p>".len()..];
            }
            (None, None) => break,
        }
    }
    out.trim().to_string()
}

/// Tente une conversion `.docx` → PDF via `soffice --headless` (LibreOffice)
/// si le binaire est présent — `None` sinon (binaire absent, conversion en
/// échec, E/S) : jamais d'erreur applicative, la conversion PDF est une
/// amélioration, pas une garantie (cf. note de module).
pub(crate) fn try_convert_to_pdf(docx_bytes: &[u8]) -> Option<Vec<u8>> {
    let dir = std::env::temp_dir().join(format!("nubia-letter-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&dir).ok()?;
    let input_path = dir.join("input.docx");
    std::fs::write(&input_path, docx_bytes).ok()?;

    let converted = std::process::Command::new("soffice")
        .args(["--headless", "--convert-to", "pdf", "--outdir"])
        .arg(&dir)
        .arg(&input_path)
        .output()
        .ok()
        .filter(|output| output.status.success())
        .and_then(|_| std::fs::read(dir.join("input.pdf")).ok());

    let _ = std::fs::remove_dir_all(&dir);
    converted
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stored_options() -> FileOptions {
        FileOptions::default().compression_method(zip::CompressionMethod::Stored)
    }

    fn build_docx(document_xml: &str) -> Vec<u8> {
        let mut buf = Vec::new();
        {
            let mut writer = ZipWriter::new(Cursor::new(&mut buf));
            writer
                .start_file("word/document.xml", stored_options())
                .unwrap();
            writer.write_all(document_xml.as_bytes()).unwrap();
            writer
                .start_file("word/styles.xml", stored_options())
                .unwrap();
            writer.write_all(b"<w:styles/>").unwrap();
            writer.finish().unwrap();
        }
        buf
    }

    fn ctx(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    fn document_xml_of(docx: &[u8]) -> String {
        let mut archive = ZipArchive::new(Cursor::new(docx)).unwrap();
        let mut xml = String::new();
        archive
            .by_name("word/document.xml")
            .unwrap()
            .read_to_string(&mut xml)
            .unwrap();
        xml
    }

    #[test]
    fn placeholders_lists_known_tokens_in_order() {
        let docx = build_docx(
            "<w:body><w:p><w:r><w:t>Bonjour {{patient.prenom}} {{ patient.nom }}</w:t></w:r></w:p></w:body>",
        );
        assert_eq!(
            placeholders(&docx).unwrap(),
            vec!["patient.prenom".to_string(), "patient.nom".to_string()]
        );
    }

    #[test]
    fn placeholders_rejects_unknown_tokens() {
        let docx =
            build_docx("<w:body><w:p><w:r><w:t>{{devis.montant}}</w:t></w:r></w:p></w:body>");
        assert_eq!(
            placeholders(&docx).unwrap_err(),
            DocxError::Unknown(vec!["devis.montant".to_string()])
        );
    }

    #[test]
    fn placeholders_rejects_a_non_docx_file() {
        assert_eq!(placeholders(b"not a zip").unwrap_err(), DocxError::NotADocx);
    }

    #[test]
    fn placeholders_rejects_a_document_xml_that_decompresses_past_the_limit() {
        // #7524 : un `document.xml` très répétitif (donc très compressible)
        // doit être rejeté sur sa taille *décompressée*, pas sur la taille
        // de l'archive reçue — ici quelques dizaines de Ko compressés pour
        // plusieurs Mo une fois inflatés.
        let mut xml = String::from("<w:body>");
        while xml.len() <= MAX_DOCUMENT_XML_SIZE {
            xml.push_str("<w:p><w:r><w:t>AAAAAAAAAA</w:t></w:r></w:p>");
        }
        xml.push_str("</w:body>");

        let mut buf = Vec::new();
        {
            let mut writer = ZipWriter::new(Cursor::new(&mut buf));
            let deflated =
                FileOptions::default().compression_method(zip::CompressionMethod::Deflated);
            writer.start_file("word/document.xml", deflated).unwrap();
            writer.write_all(xml.as_bytes()).unwrap();
            writer.finish().unwrap();
        }
        // Le fichier compressé est très petit devant `document.xml` en clair.
        assert!(buf.len() < MAX_DOCUMENT_XML_SIZE / 10);

        assert_eq!(placeholders(&buf).unwrap_err(), DocxError::TooLarge);
    }

    #[test]
    fn placeholders_rejects_an_unclosed_placeholder() {
        let docx = build_docx("<w:body><w:p><w:r><w:t>{{patient.prenom</w:t></w:r></w:p></w:body>");
        assert_eq!(placeholders(&docx).unwrap_err(), DocxError::Malformed);
    }

    #[test]
    fn render_substitutes_and_keeps_other_parts_intact() {
        let docx = build_docx(
            "<w:body><w:p><w:r><w:t>Bonjour {{patient.prenom}}</w:t></w:r></w:p></w:body>",
        );
        let out = render(&docx, &ctx(&[("patient.prenom", "Léa")])).unwrap();
        assert!(document_xml_of(&out).contains("Bonjour Léa"));

        let mut archive = ZipArchive::new(Cursor::new(&out)).unwrap();
        let mut styles = String::new();
        archive
            .by_name("word/styles.xml")
            .unwrap()
            .read_to_string(&mut styles)
            .unwrap();
        assert_eq!(styles, "<w:styles/>");
    }

    #[test]
    fn render_escapes_xml_special_characters() {
        let docx = build_docx("<w:body><w:p><w:r><w:t>{{cabinet.nom}}</w:t></w:r></w:p></w:body>");
        let out = render(&docx, &ctx(&[("cabinet.nom", "Dupont & Fils <Cabinet>")])).unwrap();
        assert!(document_xml_of(&out).contains("Dupont &amp; Fils &lt;Cabinet&gt;"));
    }

    #[test]
    fn render_rejects_missing_values() {
        let docx = build_docx("<w:body><w:p><w:r><w:t>{{rdv.date}}</w:t></w:r></w:p></w:body>");
        assert_eq!(
            render(&docx, &ctx(&[])).unwrap_err(),
            DocxError::Missing(vec!["rdv.date".to_string()])
        );
    }

    #[test]
    fn split_placeholder_across_runs_is_left_verbatim() {
        // Run coupé (mise en forme partielle) : le `{{...}}` contient une
        // balise -> jamais détecté ni substitué, cf. limite documentée en
        // tête de module.
        let docx = build_docx(
            "<w:body><w:p><w:r><w:t>{{patient.</w:t></w:r><w:r><w:t>prenom}}</w:t></w:r></w:p></w:body>",
        );
        assert_eq!(placeholders(&docx).unwrap(), Vec::<String>::new());
        let out = render(&docx, &ctx(&[])).unwrap();
        assert!(document_xml_of(&out).contains("{{patient.</w:t></w:r><w:r><w:t>prenom}}"));
    }

    #[test]
    fn extract_text_concatenates_runs_with_paragraph_breaks() {
        let docx = build_docx(
            "<w:body><w:p><w:r><w:t>Ligne un</w:t></w:r></w:p><w:p><w:r><w:t>Ligne deux</w:t></w:r></w:p></w:body>",
        );
        assert_eq!(extract_text(&docx), "Ligne un\nLigne deux");
    }

    #[test]
    fn try_convert_to_pdf_never_panics() {
        // CI/dev n'ont pas LibreOffice installé : le chemin de repli (`None`)
        // est l'issue attendue, mais on ne fige pas cette hypothèse d'environnement.
        if let Some(pdf) = try_convert_to_pdf(&build_docx("<w:body/>")) {
            assert!(pdf.starts_with(b"%PDF"));
        }
    }
}
