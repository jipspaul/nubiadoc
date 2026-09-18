//! Étiquettes de stérilisation + usage d'un sachet par scan (DP-F13.a, #7181),
//! sur le modèle existant `sterilization_cycle`/`sterilized_pouch`
//! (migrations 0190/0191/0198, complétées par 0269) :
//! - `GET  /v1/sterilization/cycles/:id/labels.pdf` — planche d'étiquettes
//!   (une par sachet du cycle : code, cycle, date de stérilisation, date de
//!   péremption, QR encodant le code du sachet), 2 colonnes, imprimable sur
//!   planches standard (format Avery L7163 / 3422 : 2 × 7 étiquettes de
//!   99,1 × 38,1 mm par page A4).
//! - `POST /v1/sterilization/pouches/:code/use` — rattache le sachet scanné
//!   à un patient (et optionnellement à une séance), idempotent.
//!
//! PDF : même mécanique « sans crate » que `prescriptions.rs` /
//! `implant_passport.rs` (structure `%PDF-1.4` minimale écrite à la main,
//! police Type1 Helvetica en WinAnsiEncoding). Le QR est dessiné en
//! rectangles vectoriels à partir de la matrice de modules du crate
//! `qrcode` (sans feature `image`), pas d'image embarquée.
//!
//! `ProSecretaryPlusClaims` (secretary/practitioner/admin/manager) : même
//! garde que `sterilization.rs` — tâche opérationnelle du cabinet, pas de
//! garde relation-de-soin.

use axum::{
    extract::{Path, Query, State},
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    prescriptions::escape_winansi,
    scheduling::format_paris_date,
    AppState,
};

/// Durée de validité par défaut d'un sachet stérilisé, en jours, à compter
/// de `sterilization_cycle.started_at` : aucune règle n'existait dans le
/// modèle (ni colonne, ni paramètre cabinet). 6 mois est la durée de
/// conservation usuelle d'un sachet simple stocké à l'abri (guide DGS/ADF
/// « Grille technique d'évaluation des cabinets dentaires »), surchargeable
/// par `?shelf_life_days=` (borné à `MAX_SHELF_LIFE_DAYS`).
pub const DEFAULT_SHELF_LIFE_DAYS: i64 = 180;
/// Borne haute de `?shelf_life_days=` (2 ans : sachet double/containers).
pub const MAX_SHELF_LIFE_DAYS: i64 = 730;

// ── Gabarit de planche (points PDF, 1 mm = 2,835 pt) ─────────────────────────
// Avery L7163 / 3422 : 2 colonnes × 7 lignes de 99,1 × 38,1 mm sur A4,
// marge haute 15,1 mm, marge gauche 4,65 mm, gouttière 2,5 mm.

const PAGE_W: f32 = 595.0;
const PAGE_H: f32 = 842.0;
const LABEL_W: f32 = 280.9;
const LABEL_H: f32 = 108.0;
const LEFT_MARGIN: f32 = 13.2;
const TOP_MARGIN: f32 = 42.8;
const COL_GAP: f32 = 7.1;
const COLUMNS: usize = 2;
const ROWS: usize = 7;
/// Nombre d'étiquettes par page (2 colonnes × 7 lignes).
pub const LABELS_PER_PAGE: usize = COLUMNS * ROWS;

/// Côté du QR (≈ 29,6 mm) et marge intérieure de l'étiquette.
const QR_SIZE: f32 = 84.0;
const LABEL_PADDING: f32 = 12.0;

/// Longueur d'affichage max du code / de la référence autoclave sur
/// l'étiquette (le QR porte toujours le code complet).
const MAX_CODE_DISPLAY_LEN: usize = 30;
const MAX_AUTOCLAVE_DISPLAY_LEN: usize = 22;

// ── GET /v1/sterilization/cycles/:id/labels.pdf ─────────────────────────────

/// Query de `GET /v1/sterilization/cycles/:id/labels.pdf`.
#[derive(Deserialize)]
pub struct LabelsQuery {
    pub shelf_life_days: Option<i64>,
}

/// Une étiquette à imprimer.
struct Label {
    code: String,
    autoclave_ref: String,
    cycle_number: i32,
    sterilized_on: String,
    expires_on: String,
    non_conforme: bool,
}

/// `GET /v1/sterilization/cycles/:id/labels.pdf` — planche d'étiquettes
/// du cycle, une par sachet (`sterilized_pouch`, tri par `code`).
///
/// Cycle inexistant/hors tenant → 404. `?shelf_life_days=` hors
/// `1..=MAX_SHELF_LIFE_DAYS` → 422 (défaut `DEFAULT_SHELF_LIFE_DAYS`).
/// Cycle sans sachet → PDF d'une page portant la mention « Aucun sachet »
/// (même choix que le passeport implantaire vide, pas d'erreur).
/// Cycle `non_conforme` → étiquettes générées quand même (traçabilité non
/// bloquante, cf. #4138) mais chacune porte la mention « CYCLE NON
/// CONFORME - ne pas utiliser ».
/// Réponse `200 Content-Type: application/pdf`, `Content-Disposition:
/// inline; filename="etiquettes-sterilisation-<autoclave>-<n>.pdf"`.
pub async fn sterilization_cycle_labels_pdf(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(cycle_id): Path<Uuid>,
    Query(params): Query<LabelsQuery>,
) -> Result<Response, AppError> {
    let shelf_life_days = params.shelf_life_days.unwrap_or(DEFAULT_SHELF_LIFE_DAYS);
    if !(1..=MAX_SHELF_LIFE_DAYS).contains(&shelf_life_days) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let cycle = sqlx::query(
        "SELECT autoclave_ref, cycle_number, started_at, status \
         FROM sterilization_cycle WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(cycle_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let autoclave_ref: String = cycle
        .try_get("autoclave_ref")
        .map_err(|_| AppError::Internal)?;
    let cycle_number: i32 = cycle
        .try_get("cycle_number")
        .map_err(|_| AppError::Internal)?;
    let started_at: chrono::DateTime<chrono::Utc> = cycle
        .try_get("started_at")
        .map_err(|_| AppError::Internal)?;
    let status: String = cycle.try_get("status").map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT code FROM sterilized_pouch \
         WHERE cycle_id = $1 AND cabinet_id = $2 ORDER BY code",
    )
    .bind(cycle_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let sterilized_on = format_paris_date(started_at);
    let expires_on = format_paris_date(started_at + chrono::Duration::days(shelf_life_days));
    let non_conforme = status == "non_conforme";

    let mut labels = Vec::with_capacity(rows.len());
    for row in &rows {
        labels.push(Label {
            code: row.try_get("code").map_err(|_| AppError::Internal)?,
            autoclave_ref: autoclave_ref.clone(),
            cycle_number,
            sterilized_on: sterilized_on.clone(),
            expires_on: expires_on.clone(),
            non_conforme,
        });
    }

    let pdf = render_labels_pdf(&labels);

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        cycle_id = %cycle_id,
        labels = labels.len(),
        "sterilization labels pdf generated"
    );

    let filename = format!(
        "etiquettes-sterilisation-{}-{}.pdf",
        filename_slug(&autoclave_ref),
        cycle_number
    );
    let disposition = HeaderValue::from_str(&format!("inline; filename=\"{filename}\""))
        .map_err(|_| AppError::Internal)?;

    Ok((
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("application/pdf"),
            ),
            (header::CONTENT_DISPOSITION, disposition),
        ],
        pdf,
    )
        .into_response())
}

/// Réduit `autoclave_ref` (texte libre) à `[A-Za-z0-9-]` pour le nom de
/// fichier — tout autre caractère devient `-`, vide → `autoclave`.
fn filename_slug(s: &str) -> String {
    let slug: String = s
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c } else { '-' })
        .collect::<String>()
        .trim_matches('-')
        .chars()
        .take(40)
        .collect();
    if slug.is_empty() {
        "autoclave".to_string()
    } else {
        slug
    }
}

/// Tronque une chaîne à `max` caractères (avec `...` si tronquée) pour
/// tenir dans la largeur de l'étiquette.
fn truncate_display(s: &str, max: usize) -> String {
    if s.chars().count() <= max {
        s.to_string()
    } else {
        let head: String = s.chars().take(max.saturating_sub(3)).collect();
        format!("{head}...")
    }
}

/// Génère la planche PDF : `LABELS_PER_PAGE` étiquettes par page, 2
/// colonnes, autant de pages que nécessaire (au moins une).
fn render_labels_pdf(labels: &[Label]) -> Vec<u8> {
    let mut pages: Vec<Vec<u8>> = Vec::new();
    if labels.is_empty() {
        let mut content: Vec<u8> = b"BT /F1 12 Tf 50 780 Td 14 TL\n(".to_vec();
        content.extend(escape_winansi(
            "Aucun sachet enregistré pour ce cycle de stérilisation.",
        ));
        content.extend_from_slice(b") Tj T*\nET");
        pages.push(content);
    }
    for chunk in labels.chunks(LABELS_PER_PAGE) {
        let mut content: Vec<u8> = Vec::new();
        for (index, label) in chunk.iter().enumerate() {
            let column = index % COLUMNS;
            let row = index / COLUMNS;
            let x0 = LEFT_MARGIN + column as f32 * (LABEL_W + COL_GAP);
            let y0 = PAGE_H - TOP_MARGIN - (row as f32 + 1.0) * LABEL_H;
            draw_label(&mut content, label, x0, y0);
        }
        pages.push(content);
    }

    // Objets : 1 Catalog, 2 Pages, 3 Helvetica, 4 Helvetica-Bold, puis par
    // page : (Page, Contents).
    let first_page_obj = 5;
    let kids: Vec<String> = (0..pages.len())
        .map(|i| format!("{} 0 R", first_page_obj + 2 * i))
        .collect();

    let mut objects: Vec<Vec<u8>> = vec![
        b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
        format!(
            "<< /Type /Pages /Kids [{}] /Count {} >>",
            kids.join(" "),
            pages.len()
        )
        .into_bytes(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
            .to_vec(),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>"
            .to_vec(),
    ];
    for (i, content) in pages.iter().enumerate() {
        let page_obj = first_page_obj + 2 * i;
        objects.push(
            format!(
                "<< /Type /Page /Parent 2 0 R \
                 /Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> \
                 /MediaBox [0 0 {PAGE_W} {PAGE_H}] /Contents {} 0 R >>",
                page_obj + 1
            )
            .into_bytes(),
        );
        let mut stream = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
        stream.extend_from_slice(content);
        stream.extend_from_slice(b"\nendstream");
        objects.push(stream);
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

/// Dessine une étiquette dont le coin bas-gauche est en `(x0, y0)` : cadre
/// de découpe (gris clair), QR à gauche, texte à droite.
fn draw_label(content: &mut Vec<u8>, label: &Label, x0: f32, y0: f32) {
    // Cadre de découpe.
    content.extend_from_slice(
        format!("q 0.75 G 0.3 w {x0:.2} {y0:.2} {LABEL_W:.2} {LABEL_H:.2} re S Q\n").as_bytes(),
    );

    // QR (matrice de modules → rectangles pleins, fusion des runs
    // horizontaux pour limiter la taille du flux).
    let qr_x = x0 + LABEL_PADDING;
    let qr_y = y0 + LABEL_PADDING;
    draw_qr(content, &label.code, qr_x, qr_y, QR_SIZE);

    // Texte.
    let text_x = qr_x + QR_SIZE + LABEL_PADDING;
    let text_top = y0 + LABEL_H - LABEL_PADDING - 11.0;
    let mut text = |font: &str, size: f32, dy: f32, s: &str| {
        content.extend_from_slice(
            format!("BT /{font} {size} Tf {text_x:.2} {:.2} Td (", text_top - dy).as_bytes(),
        );
        content.extend(escape_winansi(s));
        content.extend_from_slice(b") Tj ET\n");
    };
    text(
        "F2",
        11.0,
        0.0,
        &truncate_display(&label.code, MAX_CODE_DISPLAY_LEN),
    );
    text(
        "F1",
        9.0,
        16.0,
        &format!(
            "Cycle {} n° {}",
            truncate_display(&label.autoclave_ref, MAX_AUTOCLAVE_DISPLAY_LEN),
            label.cycle_number
        ),
    );
    text(
        "F1",
        9.0,
        30.0,
        &format!("Stérilisé le {}", label.sterilized_on),
    );
    text("F2", 9.0, 44.0, &format!("Péremption {}", label.expires_on));
    if label.non_conforme {
        text("F2", 8.0, 60.0, "CYCLE NON CONFORME - ne pas utiliser");
    }
}

/// Dessine le QR encodant `data` dans le carré `(x, y, size)`. Si le code
/// est trop long pour un QR (> ~2,9 Ko en mode octet), le QR est omis — le
/// texte de l'étiquette reste imprimé, jamais de 500 pour une étiquette.
fn draw_qr(content: &mut Vec<u8>, data: &str, x: f32, y: f32, size: f32) {
    let Ok(code) = qrcode::QrCode::with_error_correction_level(data.as_bytes(), qrcode::EcLevel::M)
    else {
        tracing::warn!(
            len = data.len(),
            "pouch code too long for a QR, label printed without QR"
        );
        return;
    };
    let width = code.width();
    if width == 0 {
        return;
    }
    let colors = code.to_colors();
    let module = size / width as f32;
    content.extend_from_slice(b"q 0 g\n");
    for row in 0..width {
        let mut col = 0;
        while col < width {
            if colors[row * width + col] != qrcode::Color::Dark {
                col += 1;
                continue;
            }
            let start = col;
            while col < width && colors[row * width + col] == qrcode::Color::Dark {
                col += 1;
            }
            let rect_x = x + start as f32 * module;
            // Origine PDF en bas : la ligne 0 du QR est en haut.
            let rect_y = y + (width - 1 - row) as f32 * module;
            let rect_w = (col - start) as f32 * module;
            content.extend_from_slice(
                format!("{rect_x:.2} {rect_y:.2} {rect_w:.2} {module:.2} re\n").as_bytes(),
            );
        }
    }
    content.extend_from_slice(b"f Q\n");
}

// ── POST /v1/sterilization/pouches/:code/use ─────────────────────────────────

/// Body de `POST /v1/sterilization/pouches/:code/use`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct UsePouchBody {
    pub patient_id: Uuid,
    pub consultation_id: Option<Uuid>,
}

/// Réponse de `POST /v1/sterilization/pouches/:code/use`.
#[derive(Serialize)]
pub struct UsePouchResponse {
    pub pouch_id: Uuid,
    pub code: String,
    pub cycle_id: Uuid,
    pub patient_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub consultation_id: Option<Uuid>,
    pub used_at: String,
    /// `true` si le sachet était déjà rattaché à ce patient avant cet appel
    /// (rejeu idempotent), `false` au premier scan.
    pub already_used: bool,
}

/// `POST /v1/sterilization/pouches/:code/use` — trace l'ouverture du sachet
/// `code` (scan du QR de l'étiquette) sur un patient.
///
/// `code` inconnu dans ce cabinet → 404. `patient_id` inexistant/hors
/// tenant → 404. `consultation_id` (si fourni) inexistant/hors tenant →
/// 404 ; d'un autre patient → 422.
/// Idempotent : sachet déjà rattaché au même patient et à la même séance
/// → 200 sans nouvelle écriture (`already_used: true`) ; même patient,
/// séance absente au premier scan et fournie maintenant → la séance est
/// complétée (200). Sachet déjà utilisé sur un AUTRE patient (ou une autre
/// séance du même patient) → `409 pouch_already_used` : un sachet est à
/// usage unique.
/// Sachet issu d'un cycle `non_conforme` → `409 pouch_cycle_non_conforme`
/// (#7243) : même signal que celui imprimé sur l'étiquette, avant toute
/// écriture.
/// Chaque première utilisation est tracée dans `audit_log`
/// (`use_sterilized_pouch` / `sterilized_pouch`), comme les voisins.
pub async fn use_sterilized_pouch(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Path(code): Path<String>,
    Json(body): Json<UsePouchBody>,
) -> Result<Json<UsePouchResponse>, AppError> {
    let code = code.trim();
    if code.is_empty() {
        return Err(AppError::ValidationError);
    }
    // #4600/#4727 : NUL byte non filtré → bind Postgres échoue, masqué en 500.
    crate::text_validation::reject_nul_byte(code)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // FOR UPDATE : deux scans concurrents du même sachet se sérialisent,
    // le second voit l'état posé par le premier.
    let pouch = sqlx::query(
        "SELECT id, cycle_id, code, patient_id, consultation_id, used_at \
         FROM sterilized_pouch WHERE cabinet_id = $1 AND code = $2 FOR UPDATE",
    )
    .bind(claims.cabinet_id)
    .bind(code)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let pouch_id: Uuid = pouch.try_get("id").map_err(|_| AppError::Internal)?;
    let cycle_id: Uuid = pouch.try_get("cycle_id").map_err(|_| AppError::Internal)?;
    let stored_code: String = pouch.try_get("code").map_err(|_| AppError::Internal)?;

    // #7243 : un sachet issu d'un cycle `non_conforme` (même signal que
    // celui imprimé sur l'étiquette, cf. `sterilization_cycle_labels_pdf`)
    // ne doit jamais être traçable comme ouvert sur un patient.
    let cycle_status: String = sqlx::query_scalar(
        "SELECT status FROM sterilization_cycle WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(cycle_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if cycle_status == "non_conforme" {
        return Err(AppError::PouchCycleNonConforme);
    }

    let current_patient: Option<Uuid> = pouch
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;
    let current_consultation: Option<Uuid> = pouch
        .try_get("consultation_id")
        .map_err(|_| AppError::Internal)?;
    let current_used_at: Option<chrono::DateTime<chrono::Utc>> =
        pouch.try_get("used_at").map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query("SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2")
        .bind(body.patient_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    if let Some(consultation_id) = body.consultation_id {
        let consultation = sqlx::query(
            "SELECT a.patient_id FROM consultation_session cs \
             JOIN appointment a ON a.id = cs.appointment_id \
             WHERE cs.id = $1 AND cs.cabinet_id = $2",
        )
        .bind(consultation_id)
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
        let consultation_patient: Uuid = consultation
            .try_get("patient_id")
            .map_err(|_| AppError::Internal)?;
        if consultation_patient != body.patient_id {
            return Err(AppError::ValidationError);
        }
    }

    // Sachet déjà utilisé : rejeu idempotent, complétion de séance, ou conflit.
    if let (Some(existing_patient), Some(used_at)) = (current_patient, current_used_at) {
        if existing_patient != body.patient_id {
            return Err(AppError::PouchAlreadyUsed);
        }
        let completes_consultation =
            current_consultation.is_none() && body.consultation_id.is_some();
        if current_consultation != body.consultation_id && !completes_consultation {
            return Err(AppError::PouchAlreadyUsed);
        }
        let consultation_id = if completes_consultation {
            sqlx::query(
                "UPDATE sterilized_pouch SET consultation_id = $1 \
                 WHERE id = $2 AND cabinet_id = $3",
            )
            .bind(body.consultation_id)
            .bind(pouch_id)
            .bind(claims.cabinet_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            audit_pouch_use(
                &mut tx,
                &claims,
                pouch_id,
                body.patient_id,
                body.consultation_id,
            )
            .await?;
            tx.commit().await.map_err(|_| AppError::Internal)?;
            body.consultation_id
        } else {
            tx.rollback().await.map_err(|_| AppError::Internal)?;
            current_consultation
        };
        return Ok(Json(UsePouchResponse {
            pouch_id,
            code: stored_code,
            cycle_id,
            patient_id: existing_patient,
            consultation_id,
            used_at: used_at.to_rfc3339(),
            already_used: true,
        }));
    }

    let row = sqlx::query(
        "UPDATE sterilized_pouch \
         SET patient_id = $1, consultation_id = $2, used_at = now(), used_by = $3 \
         WHERE id = $4 AND cabinet_id = $5 \
         RETURNING used_at",
    )
    .bind(body.patient_id)
    .bind(body.consultation_id)
    .bind(claims.sub)
    .bind(pouch_id)
    .bind(claims.cabinet_id)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let used_at: chrono::DateTime<chrono::Utc> =
        row.try_get("used_at").map_err(|_| AppError::Internal)?;

    audit_pouch_use(
        &mut tx,
        &claims,
        pouch_id,
        body.patient_id,
        body.consultation_id,
    )
    .await?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        pouch_id = %pouch_id,
        cycle_id = %cycle_id,
        patient_id = %body.patient_id,
        "sterilized pouch used on patient"
    );

    Ok(Json(UsePouchResponse {
        pouch_id,
        code: stored_code,
        cycle_id,
        patient_id: body.patient_id,
        consultation_id: body.consultation_id,
        used_at: used_at.to_rfc3339(),
        already_used: false,
    }))
}

/// Trace l'usage dans `audit_log` — zéro PII, uniquement des identifiants
/// (même convention que `cabinet_document_download.rs`).
async fn audit_pouch_use(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    claims: &ProSecretaryPlusClaims,
    pouch_id: Uuid,
    patient_id: Uuid,
    consultation_id: Option<Uuid>,
) -> Result<(), AppError> {
    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id, metadata) \
         VALUES ($1, $2, $3, 'use_sterilized_pouch', 'sterilized_pouch', $4, $5)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(pouch_id)
    .bind(serde_json::json!({
        "patient_id": patient_id,
        "consultation_id": consultation_id,
    }))
    .execute(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn label(code: &str) -> Label {
        Label {
            code: code.to_string(),
            autoclave_ref: "Autoclave-1".to_string(),
            cycle_number: 7,
            sterilized_on: "17/09/2026".to_string(),
            expires_on: "16/03/2027".to_string(),
            non_conforme: false,
        }
    }

    fn count(haystack: &[u8], needle: &[u8]) -> usize {
        haystack
            .windows(needle.len())
            .filter(|w| w == &needle)
            .count()
    }

    #[test]
    fn empty_cycle_yields_one_page() {
        let pdf = render_labels_pdf(&[]);
        assert!(pdf.starts_with(b"%PDF-1.4"));
        assert_eq!(count(&pdf, b"/Type /Page "), 1);
        assert_eq!(count(&pdf, b"/Count 1 "), 1);
    }

    #[test]
    fn one_page_per_labels_per_page_chunk() {
        let labels: Vec<Label> = (0..LABELS_PER_PAGE + 1)
            .map(|i| label(&format!("DM-{i:06}")))
            .collect();
        let pdf = render_labels_pdf(&labels);
        assert_eq!(count(&pdf, b"/Type /Page "), 2);
        assert_eq!(count(&pdf, b"/Count 2 "), 1);
        // Le QR est dessiné en rectangles pleins : au moins un `re` par étiquette.
        assert!(count(&pdf, b" re\n") >= labels.len());
        assert!(pdf.ends_with(b"%%EOF"));
    }

    #[test]
    fn slug_and_truncate() {
        assert_eq!(filename_slug("Autoclave n°1 / B"), "Autoclave-n-1---B");
        assert_eq!(filename_slug("///"), "autoclave");
        assert_eq!(truncate_display("abc", 5), "abc");
        assert_eq!(truncate_display("abcdefgh", 6), "abc...");
    }
}
