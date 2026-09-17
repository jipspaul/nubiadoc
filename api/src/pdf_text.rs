//! PDF texte minimal (#7197) — même mécanique que
//! `prescriptions::render_prescription_pdf` (#4626), `billing::render_quote_pdf`
//! (#7046) et `implant_passport::render_implant_passport_pdf` : structure
//! `%PDF-1.4` écrite à la main (catalogue, pages, police Helvetica
//! WinAnsiEncoding, un stream de contenu texte par page), **sans crate PDF**.
//!
//! Factorisé ici pour le moteur de courriers (`letters.rs`) qui a besoin de
//! deux choses que les trois rendus précédents n'ont pas : du texte de
//! longueur libre (repli à la largeur de page + pagination) et un en-tête /
//! pied répétés sur chaque page. Les trois rendus historiques ne sont pas
//! migrés dans cette PR (refactor hors scope, diff minimal).

/// Largeur utile en caractères pour Helvetica 11 pt sur une page A4 avec
/// marges de 50 pt (≈ 495 pt utiles, ≈ 5,5 pt par caractère moyen).
pub(crate) const WRAP_COLUMNS: usize = 88;

/// Lignes de corps par page, hors en-tête et pied.
const BODY_LINES_PER_PAGE: usize = 44;

/// Replie `text` en lignes d'au plus `width` caractères, à la frontière des
/// mots ; un mot plus long que `width` est coupé. Les sauts de ligne du
/// texte source sont conservés (un `\n` = une nouvelle ligne, une ligne vide
/// reste vide).
pub(crate) fn wrap_lines(text: &str, width: usize) -> Vec<String> {
    let mut out = Vec::new();
    for raw in text.split('\n') {
        let raw = raw.trim_end_matches('\r');
        if raw.trim().is_empty() {
            out.push(String::new());
            continue;
        }
        let mut current = String::new();
        for word in raw.split_whitespace() {
            let mut word = word.to_string();
            while word.chars().count() > width {
                let head: String = word.chars().take(width).collect();
                let tail: String = word.chars().skip(width).collect();
                if !current.is_empty() {
                    out.push(std::mem::take(&mut current));
                }
                out.push(head);
                word = tail;
            }
            if current.is_empty() {
                current = word;
            } else if current.chars().count() + 1 + word.chars().count() <= width {
                current.push(' ');
                current.push_str(&word);
            } else {
                out.push(std::mem::replace(&mut current, word));
            }
        }
        if !current.is_empty() {
            out.push(current);
        }
    }
    out
}

/// Construit un PDF A4 multi-pages : `header` en haut de chaque page,
/// `footer` en bas de chaque page, `body` réparti par blocs de
/// [`BODY_LINES_PER_PAGE`] lignes. Toutes les lignes sont échappées et
/// encodées WinAnsi ([`escape_winansi`]) : un `(`, `)` ou `\` dans une valeur
/// substituée ne peut pas casser le flux de contenu.
pub(crate) fn build_text_pdf(header: &[String], body: &[String], footer: &[String]) -> Vec<u8> {
    let chunks: Vec<&[String]> = if body.is_empty() {
        vec![&[]]
    } else {
        body.chunks(BODY_LINES_PER_PAGE).collect()
    };
    let page_count = chunks.len();

    // Objets : 1 catalogue, 2 pages, 3 police, puis (page, contenu) × N.
    let mut objects: Vec<Vec<u8>> = Vec::with_capacity(3 + 2 * page_count);
    objects.push(b"<< /Type /Catalog /Pages 2 0 R >>".to_vec());
    let kids: Vec<String> = (0..page_count)
        .map(|i| format!("{} 0 R", 4 + 2 * i))
        .collect();
    objects.push(
        format!(
            "<< /Type /Pages /Kids [{}] /Count {} >>",
            kids.join(" "),
            page_count
        )
        .into_bytes(),
    );
    objects.push(
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
            .to_vec(),
    );

    for (i, chunk) in chunks.iter().enumerate() {
        let page_obj = 4 + 2 * i;
        let content_obj = page_obj + 1;
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 3 0 R >> >> \
                 /MediaBox [0 0 595 842] /Contents {} 0 R >>",
                content_obj
            )
            .into_bytes(),
        );

        let mut content: Vec<u8> = Vec::new();
        // En-tête : 10 pt, en haut de page.
        content.extend_from_slice(b"BT /F1 10 Tf 50 800 Td 12 TL\n");
        for line in header {
            push_text_line(&mut content, line);
        }
        content.extend_from_slice(b"ET\n");
        // Corps : 11 pt, sous l'en-tête.
        let body_top = 800 - 12 * header.len() as i64 - 24;
        content.extend_from_slice(format!("BT /F1 11 Tf 50 {} Td 14 TL\n", body_top).as_bytes());
        for line in chunk.iter() {
            push_text_line(&mut content, line);
        }
        content.extend_from_slice(b"ET\n");
        // Pied : 9 pt, en bas de page, + numéro de page.
        let footer_top = 40 + 11 * footer.len() as i64;
        content.extend_from_slice(format!("BT /F1 9 Tf 50 {} Td 11 TL\n", footer_top).as_bytes());
        for line in footer {
            push_text_line(&mut content, line);
        }
        push_text_line(&mut content, &format!("Page {}/{}", i + 1, page_count));
        content.extend_from_slice(b"ET");

        let mut obj = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
        obj.extend_from_slice(&content);
        obj.extend_from_slice(b"\nendstream");
        objects.push(obj);
    }

    let mut pdf: Vec<u8> = b"%PDF-1.4\n".to_vec();
    let mut offsets = Vec::with_capacity(objects.len());
    for (i, obj) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.extend_from_slice(format!("{} 0 obj\n", i + 1).as_bytes());
        pdf.extend_from_slice(obj);
        pdf.extend_from_slice(b"\nendobj\n");
    }
    let xref_offset = pdf.len();
    pdf.extend_from_slice(format!("xref\n0 {}\n", objects.len() + 1).as_bytes());
    pdf.extend_from_slice(b"0000000000 65535 f \n");
    for off in &offsets {
        pdf.extend_from_slice(format!("{:010} 00000 n \n", off).as_bytes());
    }
    pdf.extend_from_slice(
        format!(
            "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
            objects.len() + 1,
            xref_offset
        )
        .as_bytes(),
    );
    pdf
}

fn push_text_line(content: &mut Vec<u8>, line: &str) {
    content.push(b'(');
    content.extend(escape_winansi(line));
    content.extend_from_slice(b") Tj T*\n");
}

/// Convertit un caractère Unicode en octet WinAnsiEncoding (PDF, ~ Windows-1252).
/// `None` pour tout caractère hors de cet encodage mono-octet (translittéré en `?`
/// par l'appelant) : impossible de représenter fidèlement, mais on ne doit jamais
/// écrire de l'UTF-8 multi-octets brut dans le flux de contenu d'une police simple.
fn winansi_byte(c: char) -> Option<u8> {
    let cp = c as u32;
    match cp {
        0x00..=0x7f | 0xa0..=0xff => Some(cp as u8),
        0x20ac => Some(0x80),
        0x201a => Some(0x82),
        0x0192 => Some(0x83),
        0x201e => Some(0x84),
        0x2026 => Some(0x85),
        0x2020 => Some(0x86),
        0x2021 => Some(0x87),
        0x02c6 => Some(0x88),
        0x2030 => Some(0x89),
        0x0160 => Some(0x8a),
        0x2039 => Some(0x8b),
        0x0152 => Some(0x8c),
        0x017d => Some(0x8e),
        0x2018 => Some(0x91),
        0x2019 => Some(0x92),
        0x201c => Some(0x93),
        0x201d => Some(0x94),
        0x2022 => Some(0x95),
        0x2013 => Some(0x96),
        0x2014 => Some(0x97),
        0x02dc => Some(0x98),
        0x2122 => Some(0x99),
        0x0161 => Some(0x9a),
        0x203a => Some(0x9b),
        0x0153 => Some(0x9c),
        0x017e => Some(0x9e),
        0x0178 => Some(0x9f),
        _ => None,
    }
}

/// Échappe une chaîne pour une chaîne littérale PDF `(...)` et l'encode en
/// WinAnsiEncoding (mono-octet), cohérent avec `/Encoding /WinAnsiEncoding`
/// déclaré sur la police. Les caractères de contrôle (hors tabulation) sont
/// remplacés par un espace : un `\r`/`\n` brut dans une valeur substituée ne
/// doit pas pouvoir casser ni réordonner le flux de contenu.
pub(crate) fn escape_winansi(s: &str) -> Vec<u8> {
    let mut out = Vec::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.extend_from_slice(b"\\\\"),
            '(' => out.extend_from_slice(b"\\("),
            ')' => out.extend_from_slice(b"\\)"),
            '\t' => out.push(b' '),
            c if c.is_control() => out.push(b' '),
            _ => out.push(winansi_byte(c).unwrap_or(b'?')),
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wrap_lines_respects_width_and_blank_lines() {
        let text =
            "Bonjour Madame Dupont, ceci est une phrase assez longue pour être repliée.\n\nFin.";
        let lines = wrap_lines(text, 30);
        assert!(lines.iter().all(|l| l.chars().count() <= 30));
        assert_eq!(lines[lines.len() - 2], "");
        assert_eq!(lines[lines.len() - 1], "Fin.");
        assert_eq!(lines[0], "Bonjour Madame Dupont, ceci");
    }

    #[test]
    fn wrap_lines_splits_overlong_word() {
        let lines = wrap_lines("aaaaaaaaaaaa bb", 5);
        assert_eq!(lines, vec!["aaaaa", "aaaaa", "aa bb"]);
    }

    #[test]
    fn escape_winansi_escapes_delimiters_and_controls() {
        let out = escape_winansi("a(b)c\\d\ne\u{e9}");
        assert_eq!(out, b"a\\(b\\)c\\\\d e\xe9".to_vec());
    }

    #[test]
    fn build_text_pdf_is_valid_and_paginates() {
        let header = vec!["Cabinet".to_string()];
        let footer = vec!["Pied".to_string()];
        let body: Vec<String> = (0..100).map(|i| format!("ligne {i}")).collect();
        let pdf = build_text_pdf(&header, &body, &footer);
        assert!(pdf.starts_with(b"%PDF-1.4"));
        assert!(pdf.ends_with(b"%%EOF"));
        let text = String::from_utf8_lossy(&pdf);
        assert!(text.contains("/Count 3"));
        assert!(text.contains("(Page 3/3) Tj"));
        assert!(text.contains("(ligne 99) Tj"));
    }

    #[test]
    fn build_text_pdf_empty_body_has_one_page() {
        let pdf = build_text_pdf(&[], &[], &[]);
        let text = String::from_utf8_lossy(&pdf);
        assert!(text.contains("/Count 1"));
        assert!(text.contains("(Page 1/1) Tj"));
    }
}
