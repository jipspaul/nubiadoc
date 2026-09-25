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
    build_text_pdf_with_stamps(header, body, footer, None, None)
}

/// Comme [`build_text_pdf`], avec en plus la signature et/ou le tampon du
/// praticien apposés en bas de la DERNIÈRE page (#7148) — `None` pour l'un
/// ou l'autre si le praticien n'a pas (encore) téléversé l'image
/// correspondante (`provider.signature_image_id`/`stamp_image_id`,
/// migration 0299), auquel cas le PDF produit est identique à
/// `build_text_pdf`.
pub(crate) fn build_text_pdf_with_stamps(
    header: &[String],
    body: &[String],
    footer: &[String],
    signature: Option<&JpegImage>,
    stamp: Option<&JpegImage>,
) -> Vec<u8> {
    let chunks: Vec<&[String]> = if body.is_empty() {
        vec![&[]]
    } else {
        body.chunks(BODY_LINES_PER_PAGE).collect()
    };
    let page_count = chunks.len();

    // Objets : 1 catalogue, 2 pages, 3 police, puis (page, contenu) × N,
    // puis les éventuels XObjects image (signature/tampon, dernière page).
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

    // Les XObjects image prendront les numéros d'objet juste après tous les
    // (page, contenu) déjà réservés ci-dessus (3 + 2 * page_count objets).
    let first_stamp_obj = 4 + 2 * page_count;
    let (stamp_objects, stamp_resources, stamp_ops) =
        stamp_placement(signature, stamp, first_stamp_obj);

    for (i, chunk) in chunks.iter().enumerate() {
        let page_obj = 4 + 2 * i;
        let content_obj = page_obj + 1;
        let is_last = i + 1 == page_count;
        let resources = if is_last && !stamp_resources.is_empty() {
            format!("<< /Font << /F1 3 0 R >> /XObject <<{stamp_resources} >> >>")
        } else {
            "<< /Font << /F1 3 0 R >> >>".to_string()
        };
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R /Resources {resources} \
                 /MediaBox [0 0 595 842] /Contents {content_obj} 0 R >>"
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
        // Signature/tampon (#7148) : opérateurs graphiques hors bloc texte,
        // uniquement sur la dernière page.
        if is_last && !stamp_ops.is_empty() {
            content.push(b'\n');
            content.extend_from_slice(&stamp_ops);
        }

        let mut obj = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
        obj.extend_from_slice(&content);
        obj.extend_from_slice(b"\nendstream");
        objects.push(obj);
    }

    objects.extend(stamp_objects);

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

/// Image JPEG baseline (signature ou tampon scanné du praticien, #7148) à
/// apposer sur un PDF généré. Les octets JPEG sont réinjectés tels quels
/// dans un flux `/Filter /DCTDecode` — pas de décodage pixel ni de
/// recompression, cohérent avec l'absence de dépendance PDF du reste de ce
/// module. PNG non géré : rejouer son filtrage par ligne (Paeth/Up/Sub/
/// Average) demanderait une dépendance externe — les endpoints d'upload de
/// signature/tampon (`cabinet_provider_stamp.rs`) n'acceptent donc que JPEG.
pub(crate) struct JpegImage {
    bytes: Vec<u8>,
    width_px: u32,
    height_px: u32,
    gray: bool,
}

impl JpegImage {
    /// Lit dimensions et nombre de composantes depuis le marqueur SOF —
    /// suffisant pour poser `/Width`, `/Height` et `/ColorSpace` sans
    /// décoder les pixels. `None` si `bytes` n'a pas de marqueur SOF valide
    /// avant la fin du flux ou avant `SOS` (pas un JPEG reconnu).
    pub(crate) fn parse(bytes: Vec<u8>) -> Option<Self> {
        if bytes.len() < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8 {
            return None;
        }
        let mut i = 2usize;
        while i < bytes.len() {
            while bytes.get(i) == Some(&0xFF) {
                i += 1;
            }
            let marker = *bytes.get(i)?;
            i += 1;
            if marker == 0xD9 {
                return None; // EOI sans SOF rencontré.
            }
            if (0xD0..=0xD7).contains(&marker) || marker == 0x01 {
                continue; // Marqueurs sans champ de longueur (RST*, TEM).
            }
            let hi = *bytes.get(i)? as usize;
            let lo = *bytes.get(i + 1)? as usize;
            let seg_len = (hi << 8) | lo;
            if seg_len < 2 || i + seg_len > bytes.len() {
                return None;
            }
            let is_sof = matches!(
                marker,
                0xC0..=0xC3 | 0xC5..=0xC7 | 0xC9..=0xCB | 0xCD..=0xCF
            );
            if is_sof {
                if seg_len < 8 {
                    return None;
                }
                let height = ((bytes[i + 3] as u32) << 8) | bytes[i + 4] as u32;
                let width = ((bytes[i + 5] as u32) << 8) | bytes[i + 6] as u32;
                let components = bytes[i + 7];
                if width == 0 || height == 0 {
                    return None;
                }
                return Some(JpegImage {
                    bytes,
                    width_px: width,
                    height_px: height,
                    gray: components == 1,
                });
            }
            if marker == 0xDA {
                return None; // Début du scan entropique sans SOF rencontré.
            }
            i += seg_len;
        }
        None
    }
}

fn jpeg_xobject(img: &JpegImage) -> Vec<u8> {
    let colorspace = if img.gray {
        "/DeviceGray"
    } else {
        "/DeviceRGB"
    };
    let mut obj = format!(
        "<< /Type /XObject /Subtype /Image /Width {} /Height {} /ColorSpace {} \
         /BitsPerComponent 8 /Filter /DCTDecode /Length {} >>\nstream\n",
        img.width_px,
        img.height_px,
        colorspace,
        img.bytes.len()
    )
    .into_bytes();
    obj.extend_from_slice(&img.bytes);
    obj.extend_from_slice(b"\nendstream");
    obj
}

/// Ajuste `img` dans une boîte `max_w` × `max_h` (points PDF) en conservant
/// son ratio largeur/hauteur.
fn fit_box(img: &JpegImage, max_w: f32, max_h: f32) -> (f32, f32) {
    let scale = (max_w / img.width_px as f32).min(max_h / img.height_px as f32);
    (img.width_px as f32 * scale, img.height_px as f32 * scale)
}

/// Construit les objets XObject `/Image`, le fragment `/XObject` à insérer
/// dans le dictionnaire `/Resources` d'une page, et les opérateurs `cm ...
/// Do` qui posent signature (à gauche) puis tampon (à droite) en bas de
/// page. `first_obj_num` = numéro du premier objet PDF libre — les
/// XObjects prennent les numéros suivants, dans l'ordre signature puis
/// tampon. Retourne des valeurs vides si `signature` et `stamp` sont tous
/// deux `None`.
pub(crate) fn stamp_placement(
    signature: Option<&JpegImage>,
    stamp: Option<&JpegImage>,
    first_obj_num: usize,
) -> (Vec<Vec<u8>>, String, Vec<u8>) {
    let mut objects = Vec::new();
    let mut resources = String::new();
    let mut ops = Vec::new();
    let mut next_obj = first_obj_num;
    let mut x = 320.0f32;
    const Y: f32 = 95.0;
    for (img, max_w, max_h, slot_width) in [
        (signature, 120.0f32, 55.0f32, 140.0f32),
        (stamp, 90.0f32, 90.0f32, 100.0f32),
    ] {
        let Some(img) = img else { continue };
        let (w, h) = fit_box(img, max_w, max_h);
        let name = format!("ImS{next_obj}");
        objects.push(jpeg_xobject(img));
        resources.push_str(&format!(" /{name} {next_obj} 0 R"));
        ops.extend_from_slice(format!("q {w} 0 0 {h} {x} {Y} cm /{name} Do Q\n").as_bytes());
        next_obj += 1;
        x += slot_width;
    }
    (objects, resources, ops)
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

    /// JPEG minimal (SOI + SOF0 + EOI, pas de données entropiques) —
    /// suffisant pour `JpegImage::parse`, qui ne lit que les marqueurs.
    fn fake_jpeg(width: u16, height: u16, components: u8) -> Vec<u8> {
        let mut b = vec![0xFFu8, 0xD8]; // SOI
        b.extend_from_slice(&[0xFF, 0xC0]); // SOF0
        let seg_len = 2 + 1 + 2 + 2 + 1 + 3 * components as usize;
        b.push((seg_len >> 8) as u8);
        b.push((seg_len & 0xFF) as u8);
        b.push(8); // precision
        b.push((height >> 8) as u8);
        b.push((height & 0xFF) as u8);
        b.push((width >> 8) as u8);
        b.push((width & 0xFF) as u8);
        b.push(components);
        for c in 0..components {
            b.extend_from_slice(&[c + 1, 0x11, 0]);
        }
        b.extend_from_slice(&[0xFF, 0xD9]); // EOI
        b
    }

    #[test]
    fn jpeg_image_parse_reads_dimensions_and_colorspace() {
        let rgb = JpegImage::parse(fake_jpeg(200, 100, 3)).unwrap();
        assert_eq!((rgb.width_px, rgb.height_px, rgb.gray), (200, 100, false));

        let gray = JpegImage::parse(fake_jpeg(50, 60, 1)).unwrap();
        assert_eq!((gray.width_px, gray.height_px, gray.gray), (50, 60, true));
    }

    #[test]
    fn jpeg_image_parse_rejects_non_jpeg() {
        assert!(JpegImage::parse(b"not a jpeg".to_vec()).is_none());
        assert!(JpegImage::parse(b"%PDF-1.4".to_vec()).is_none());
        assert!(JpegImage::parse(vec![]).is_none());
    }

    #[test]
    fn stamp_placement_is_empty_without_images() {
        let (objects, resources, ops) = stamp_placement(None, None, 10);
        assert!(objects.is_empty());
        assert_eq!(resources, "");
        assert!(ops.is_empty());
    }

    #[test]
    fn build_text_pdf_with_stamps_embeds_xobjects_on_last_page_only() {
        let header = vec!["Cabinet".to_string()];
        let footer = vec!["Pied".to_string()];
        let body: Vec<String> = (0..100).map(|i| format!("ligne {i}")).collect();
        let signature = JpegImage::parse(fake_jpeg(300, 120, 3)).unwrap();
        let stamp = JpegImage::parse(fake_jpeg(80, 80, 1)).unwrap();
        let pdf =
            build_text_pdf_with_stamps(&header, &body, &footer, Some(&signature), Some(&stamp));
        assert!(pdf.starts_with(b"%PDF-1.4"));
        assert!(pdf.ends_with(b"%%EOF"));
        let text = String::from_utf8_lossy(&pdf);
        assert!(text.contains("/Count 3"));
        // Un seul dictionnaire /Resources référence des XObjects : la
        // dernière page uniquement.
        assert_eq!(text.matches("/XObject <<").count(), 1);
        assert_eq!(text.matches("/Subtype /Image").count(), 2);
        assert!(text.contains("/ColorSpace /DeviceRGB"));
        assert!(text.contains("/ColorSpace /DeviceGray"));
        assert!(text.contains("/Filter /DCTDecode"));
    }

    #[test]
    fn build_text_pdf_without_stamps_is_unchanged() {
        // Non-régression : `build_text_pdf` (sans signature/tampon) produit
        // toujours le même contenu qu'avant #7148.
        let header = vec!["Cabinet".to_string()];
        let footer = vec!["Pied".to_string()];
        let body = vec!["Une ligne.".to_string()];
        let pdf = build_text_pdf(&header, &body, &footer);
        let text = String::from_utf8_lossy(&pdf);
        assert!(!text.contains("/XObject"));
        assert!(!text.contains("/Subtype /Image"));
    }
}
