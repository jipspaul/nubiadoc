//! `GET /v1/cabinet/vcard` + `GET /v1/cabinet/vcard/qr.png` (DP-F26.a, #7146)
//! — carte de visite du cabinet : vCard 4.0 (`.vcf`) et un QR encodant cette
//! même vCard, pour partage/impression/envoi au patient depuis le dashboard
//! praticien.
//!
//! Le QR est généré avec le crate `qrcode` (déjà en dépendance, matrice de
//! modules — cf. `sterilization_labels.rs`), puis encodé en PNG à la main :
//! même doctrine que `sterilization_labels.rs`/`prescriptions.rs`
//! (« sans crate » pour un format simple) plutôt que d'ajouter une
//! dépendance au crate `image` juste pour ce petit lot. Le PNG produit est
//! un niveau de gris 8 bits non entrelacé, compressé via des blocs DEFLATE
//! "stored" (non compressés, RFC 1951 §3.2.4) — valide au sens du format
//! PNG, qui n'impose pas de compression réelle des données `IDAT`.

use axum::{
    extract::State,
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
};
use sqlx::Row;

use crate::{
    auth::{AppError, ProMemberClaims},
    AppState,
};

/// Échappe les caractères spéciaux d'une valeur de propriété vCard
/// (RFC 6350 §3.4) : `\`, `,`, `;` et les sauts de ligne.
fn vcard_escape(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(',', "\\,")
        .replace(';', "\\;")
        .replace('\n', "\\n")
}

/// Construit le texte vCard 4.0 du cabinet à partir de `raison_sociale` et
/// de `settings` (`contact.phone`/`contact.email` — même shape que
/// `cabinet_info::get_cabinet_info`). `address` peut être soit une chaîne à
/// plat (forme écrite par `PATCH /v1/cabinet`, cf. `auth::patch_cabinet`),
/// soit un objet `{rue, cp, ville}` : les deux formes sont acceptées.
/// `KIND:org` marque explicitement qu'il s'agit d'une carte de cabinet, pas
/// d'une personne.
fn build_vcard(name: &str, settings: &serde_json::Value) -> String {
    let mut lines = vec![
        "BEGIN:VCARD".to_string(),
        "VERSION:4.0".to_string(),
        "KIND:org".to_string(),
        format!("FN:{}", vcard_escape(name)),
        format!("ORG:{}", vcard_escape(name)),
    ];

    let contact = settings.get("contact");
    let phone = contact
        .and_then(|c| c.get("phone").or_else(|| c.get("telephone")))
        .and_then(|v| v.as_str());
    let email = contact
        .and_then(|c| c.get("email"))
        .and_then(|v| v.as_str());

    if let Some(phone) = phone {
        lines.push(format!("TEL;TYPE=work,voice:{}", vcard_escape(phone)));
    }
    if let Some(email) = email {
        lines.push(format!("EMAIL;TYPE=work:{}", vcard_escape(email)));
    }

    let address = settings.get("address");
    let address_str = address.and_then(|a| a.as_str());
    let (rue, cp, ville) = if let Some(flat) = address_str.filter(|s| !s.is_empty()) {
        (Some(flat), None, None)
    } else {
        (
            address.and_then(|a| a.get("rue")).and_then(|v| v.as_str()),
            address.and_then(|a| a.get("cp")).and_then(|v| v.as_str()),
            address
                .and_then(|a| a.get("ville"))
                .and_then(|v| v.as_str()),
        )
    };
    if rue.is_some() || cp.is_some() || ville.is_some() {
        lines.push(format!(
            "ADR;TYPE=work:;;{};{};;{};",
            vcard_escape(rue.unwrap_or("")),
            vcard_escape(ville.unwrap_or("")),
            vcard_escape(cp.unwrap_or("")),
        ));
    }

    lines.push("END:VCARD".to_string());
    // RFC 6350 §3.2 : fins de ligne CRLF obligatoires.
    lines.join("\r\n") + "\r\n"
}

/// Charge `raison_sociale`/`settings` du cabinet courant (GUC déjà posé par
/// l'appelant) et construit la vCard.
async fn load_cabinet_vcard(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: uuid::Uuid,
) -> Result<String, AppError> {
    let row = sqlx::query("SELECT raison_sociale, settings FROM cabinet WHERE id = $1")
        .bind(cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let name: String = row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let settings: serde_json::Value = row.try_get("settings").map_err(|_| AppError::Internal)?;

    Ok(build_vcard(&name, &settings))
}

/// `GET /v1/cabinet/vcard` — vCard 4.0 du cabinet courant (`ProMemberClaims`
/// : tout membre pro du cabinet, même garde que `GET /v1/cabinet`).
pub async fn get_cabinet_vcard(
    State(state): State<AppState>,
    claims: ProMemberClaims,
) -> Result<Response, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let vcard = load_cabinet_vcard(&mut tx, claims.cabinet_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        "cabinet vcard generated"
    );

    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("text/vcard; charset=utf-8"),
            ),
            (
                header::CONTENT_DISPOSITION,
                HeaderValue::from_static("inline; filename=\"cabinet.vcf\""),
            ),
        ],
        vcard,
    )
        .into_response())
}

/// `GET /v1/cabinet/vcard/qr.png` — QR (PNG) encodant la même vCard que
/// `GET /v1/cabinet/vcard`, lisible directement (contact importable sans
/// appel API par le destinataire qui scanne).
pub async fn get_cabinet_vcard_qr_png(
    State(state): State<AppState>,
    claims: ProMemberClaims,
) -> Result<Response, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let vcard = load_cabinet_vcard(&mut tx, claims.cabinet_id).await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let png = qr_png(&vcard)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        "cabinet vcard qr generated"
    );

    Ok((
        StatusCode::OK,
        [(header::CONTENT_TYPE, HeaderValue::from_static("image/png"))],
        png,
    )
        .into_response())
}

// ── Encodage QR → PNG (sans crate `image`) ───────────────────────────────

/// Taille d'un module QR à l'affichage, en pixels.
const QR_MODULE_PX: u32 = 8;
/// Zone de silence autour du QR, en modules (recommandation QR standard).
const QR_QUIET_MODULES: u32 = 4;

/// Encode `data` en QR (niveau de correction M, comme `sterilization_labels.rs`)
/// puis rend la matrice de modules en PNG niveaux de gris 8 bits.
fn qr_png(data: &str) -> Result<Vec<u8>, AppError> {
    let code = qrcode::QrCode::with_error_correction_level(data.as_bytes(), qrcode::EcLevel::M)
        .map_err(|_| AppError::Internal)?;
    let modules = code.width();
    if modules == 0 {
        return Err(AppError::Internal);
    }
    let colors = code.to_colors();
    let modules_u32 = modules as u32;
    let size_modules = modules_u32 + 2 * QR_QUIET_MODULES;
    let size_px = size_modules * QR_MODULE_PX;

    // Une ligne = un octet de filtre PNG (0 = "None") + `size_px` échantillons.
    let mut raw = Vec::with_capacity((size_px as usize) * (1 + size_px as usize));
    for py in 0..size_px {
        raw.push(0u8);
        let module_row = py / QR_MODULE_PX;
        for px in 0..size_px {
            let module_col = px / QR_MODULE_PX;
            let dark = module_row >= QR_QUIET_MODULES
                && module_col >= QR_QUIET_MODULES
                && module_row < QR_QUIET_MODULES + modules_u32
                && module_col < QR_QUIET_MODULES + modules_u32
                && colors[((module_row - QR_QUIET_MODULES) * modules_u32
                    + (module_col - QR_QUIET_MODULES)) as usize]
                    == qrcode::Color::Dark;
            raw.push(if dark { 0x00 } else { 0xFF });
        }
    }

    let idat = zlib_compress(&raw);

    let mut ihdr = Vec::with_capacity(13);
    ihdr.extend_from_slice(&size_px.to_be_bytes());
    ihdr.extend_from_slice(&size_px.to_be_bytes());
    // Profondeur 8 bits, type de couleur 0 (niveaux de gris), compression/
    // filtre/entrelacement standards (0).
    ihdr.extend_from_slice(&[8, 0, 0, 0, 0]);

    let mut png = Vec::new();
    png.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    png.extend_from_slice(&png_chunk(b"IHDR", &ihdr));
    png.extend_from_slice(&png_chunk(b"IDAT", &idat));
    png.extend_from_slice(&png_chunk(b"IEND", &[]));
    Ok(png)
}

/// Construit un chunk PNG complet (longueur + type + données + CRC32).
fn png_chunk(kind: &[u8; 4], data: &[u8]) -> Vec<u8> {
    let mut chunk = Vec::with_capacity(12 + data.len());
    chunk.extend_from_slice(&(data.len() as u32).to_be_bytes());
    chunk.extend_from_slice(kind);
    chunk.extend_from_slice(data);

    let mut crc_input = Vec::with_capacity(4 + data.len());
    crc_input.extend_from_slice(kind);
    crc_input.extend_from_slice(data);
    chunk.extend_from_slice(&crc32(&crc_input).to_be_bytes());
    chunk
}

/// Flux zlib (RFC 1950) autour de `data` : en-tête fixe (méthode deflate,
/// fenêtre 32 Ko, pas de dictionnaire), données compressées en blocs DEFLATE
/// "stored" (non compressés), puis Adler-32.
fn zlib_compress(data: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(data.len() + data.len() / 65535 * 5 + 13);
    out.extend_from_slice(&[0x78, 0x01]);
    out.extend_from_slice(&deflate_stored(data));
    out.extend_from_slice(&adler32(data).to_be_bytes());
    out
}

/// Encode `data` en flux DEFLATE (RFC 1951) fait uniquement de blocs
/// "stored" (BTYPE=00, §3.2.4) — aucune compression réelle, mais un flux
/// DEFLATE valide, largement suffisant pour un petit QR généré à la volée.
fn deflate_stored(data: &[u8]) -> Vec<u8> {
    const MAX_BLOCK: usize = 65_535;
    let mut out = Vec::with_capacity(data.len() + (data.len() / MAX_BLOCK + 1) * 5);

    if data.is_empty() {
        out.push(1u8); // BFINAL=1, BTYPE=00, reste du dernier bloc à 0
        out.extend_from_slice(&0u16.to_le_bytes());
        out.extend_from_slice(&0xFFFFu16.to_le_bytes());
        return out;
    }

    let mut offset = 0usize;
    while offset < data.len() {
        let remaining = data.len() - offset;
        let chunk_len = remaining.min(MAX_BLOCK);
        let is_last = offset + chunk_len == data.len();
        // En-tête de bloc "stored" : 3 bits (BFINAL, BTYPE=00) + complément
        // à l'octet — comme BTYPE=00, l'octet entier vaut simplement BFINAL.
        out.push(if is_last { 1 } else { 0 });
        let len = chunk_len as u16;
        out.extend_from_slice(&len.to_le_bytes());
        out.extend_from_slice(&(!len).to_le_bytes());
        out.extend_from_slice(&data[offset..offset + chunk_len]);
        offset += chunk_len;
    }
    out
}

/// Adler-32 (RFC 1950 §8.2), utilisé comme trailer du flux zlib.
fn adler32(data: &[u8]) -> u32 {
    const MOD_ADLER: u32 = 65_521;
    let mut a: u32 = 1;
    let mut b: u32 = 0;
    for &byte in data {
        a = (a + byte as u32) % MOD_ADLER;
        b = (b + a) % MOD_ADLER;
    }
    (b << 16) | a
}

/// CRC-32 (ISO 3309 / RFC 1952 annexe 8), utilisé pour les chunks PNG.
fn crc32(data: &[u8]) -> u32 {
    let mut crc: u32 = 0xFFFF_FFFF;
    for &byte in data {
        crc ^= byte as u32;
        for _ in 0..8 {
            let mask = 0u32.wrapping_sub(crc & 1);
            crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
        }
    }
    !crc
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_vcard_contains_mandatory_fields() {
        let settings = serde_json::json!({
            "contact": { "phone": "0102030405", "email": "cabinet@nubia.test" },
            "address": { "rue": "12 rue de la Paix", "cp": "75001", "ville": "Paris" },
        });
        let vcard = build_vcard("Cabinet Dentaire Nubia", &settings);

        assert!(vcard.starts_with("BEGIN:VCARD\r\n"));
        assert!(vcard.ends_with("END:VCARD\r\n"));
        assert!(vcard.contains("VERSION:4.0\r\n"));
        assert!(vcard.contains("FN:Cabinet Dentaire Nubia\r\n"));
        assert!(vcard.contains("TEL;TYPE=work,voice:0102030405\r\n"));
        assert!(vcard.contains("EMAIL;TYPE=work:cabinet@nubia.test\r\n"));
        assert!(vcard.contains("ADR;TYPE=work:;;12 rue de la Paix;Paris;;75001;\r\n"));
    }

    #[test]
    fn build_vcard_accepts_flat_string_address() {
        // Forme réellement écrite par `PATCH /v1/cabinet` (auth::patch_cabinet) :
        // `settings.address` est une chaîne à plat, pas un objet {rue, cp, ville}.
        let settings = serde_json::json!({
            "contact": { "phone": "+33478920011" },
            "address": "12 rue de la Republique, 69002 Lyon",
        });
        let vcard = build_vcard("Cabinet Lyon", &settings);

        assert!(vcard.contains("TEL;TYPE=work,voice:+33478920011\r\n"));
        assert!(vcard.contains("ADR;TYPE=work:;;12 rue de la Republique\\, 69002 Lyon;;;;\r\n"));
    }

    #[test]
    fn build_vcard_escapes_special_characters() {
        let settings = serde_json::json!({});
        let vcard = build_vcard("Cabinet; Dupont, Martin\\Test", &settings);
        assert!(vcard.contains("FN:Cabinet\\; Dupont\\, Martin\\\\Test\r\n"));
    }

    #[test]
    fn build_vcard_without_contact_or_address_stays_minimal() {
        let settings = serde_json::json!({});
        let vcard = build_vcard("Cabinet Minimal", &settings);
        assert!(!vcard.contains("TEL;"));
        assert!(!vcard.contains("EMAIL;"));
        assert!(!vcard.contains("ADR;"));
    }

    /// Le PNG produit doit être un PNG valide : signature, IHDR bien formé,
    /// et le flux `IDAT` doit se décompresser (zlib "stored") pour retrouver
    /// exactement l'image brute (filtre + pixels) qu'on a construite.
    #[test]
    fn qr_png_produces_a_valid_png_with_matching_ihdr() {
        let png = qr_png("BEGIN:VCARD\r\nVERSION:4.0\r\nFN:Test\r\nEND:VCARD\r\n")
            .expect("QR généré pour une vCard courte");

        assert!(png.starts_with(b"\x89PNG\r\n\x1a\n"));

        // Chunk IHDR juste après la signature (8 octets) + longueur(4) + type(4).
        let ihdr_type = &png[12..16];
        assert_eq!(ihdr_type, b"IHDR");
        let width = u32::from_be_bytes(png[16..20].try_into().unwrap());
        let height = u32::from_be_bytes(png[20..24].try_into().unwrap());
        assert_eq!(width, height, "QR carré");
        assert!(width > 0);
        let bit_depth = png[24];
        let color_type = png[25];
        assert_eq!(bit_depth, 8);
        assert_eq!(color_type, 0);

        assert!(png.ends_with(&png_chunk(b"IEND", &[])));
    }

    #[test]
    fn deflate_roundtrip_via_hand_rolled_inflate() {
        let data = b"une petite charge utile repetee ".repeat(5000);
        let compressed = zlib_compress(&data);
        // En-tête zlib fixe.
        assert_eq!(&compressed[0..2], &[0x78, 0x01]);
        let decompressed = inflate_stored_for_test(&compressed);
        assert_eq!(decompressed, data);
    }

    /// Décodeur minimal du sous-ensemble DEFLATE produit par
    /// `deflate_stored` (blocs "stored" uniquement) — sert uniquement à
    /// vérifier par un chemin indépendant que l'encodeur ci-dessus produit
    /// un flux DEFLATE valide et fidèle.
    fn inflate_stored_for_test(zlib_stream: &[u8]) -> Vec<u8> {
        let deflate = &zlib_stream[2..zlib_stream.len() - 4];
        let mut out = Vec::new();
        let mut pos = 0usize;
        loop {
            let bfinal = deflate[pos] & 1;
            pos += 1;
            let len = u16::from_le_bytes([deflate[pos], deflate[pos + 1]]) as usize;
            pos += 4; // LEN + NLEN
            out.extend_from_slice(&deflate[pos..pos + len]);
            pos += len;
            if bfinal == 1 {
                break;
            }
        }
        out
    }
}
