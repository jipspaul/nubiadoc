//! Handlers CR structuré (#7154) : `PUT`/`GET /v1/cabinet/consultations/:id/cr`,
//! `POST /v1/cabinet/consultations/:id/cr/finalize`,
//! `GET /v1/cabinet/consultations/:id/cr/render`.
//!
//! S'appuie sur `consultation_cr` (migration 0297, #7154) : brouillon
//! structuré d'une séance (`consultation_session`, `:id` du path — même
//! convention que `consultations::set_consultation_note`), sauvegardé à
//! chaque frappe (`PUT`, idempotent) tant qu'il n'est pas finalisé, puis
//! rendu en texte/PDF et recopié dans `consultation_clinique` (compte rendu
//! patient, migration 0113) à la finalisation. Une section `implant`
//! renseignée alimente le passeport implantaire (`implant_passport`,
//! #4140) — upsert sur `consultation_cr.implant_passport_id` pour rester
//! idempotent au fil des autosaves plutôt que de créer un implant par frappe.

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
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Une section rédigée du CR structuré (clé stable, ex. `"diagnostic"`,
/// utilisée par le front pour retrouver la section entre deux autosaves).
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct CrSection {
    pub key: String,
    pub title: String,
    pub content: String,
}

/// Renseignements de la section implant (#7154) — alimente `implant_passport`.
/// La garde §14 (relation de soin) est déjà vérifiée via la séance elle-même,
/// pas revalidée ici.
#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct ImplantSectionInput {
    pub brand: String,
    pub implant_ref: String,
    #[serde(default)]
    pub lot_number: Option<String>,
    #[serde(default)]
    pub placement_date: Option<String>,
    #[serde(default)]
    pub tooth_position: Option<String>,
    #[serde(default)]
    pub notes: Option<String>,
}

/// Plafonds métier réalistes (même logique que `cr_templates.rs::MAX_CR_TEMPLATE_TITLE_LEN`,
/// #7226) — un CR structuré reste une poignée de sections rédigées, pas un
/// document libre non borné.
const MAX_CR_SECTIONS: usize = 50;
const MAX_CR_SECTION_KEY_LEN: usize = 100;
const MAX_CR_SECTION_TITLE_LEN: usize = 200;
const MAX_CR_SECTION_CONTENT_LEN: usize = 20_000;

// ── PUT /v1/cabinet/consultations/:id/cr ──────────────────────────────────────

/// Corps de `PUT /v1/cabinet/consultations/:id/cr`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct SaveConsultationCrBody {
    #[serde(default)]
    pub template_id: Option<Uuid>,
    pub sections: Vec<CrSection>,
    #[serde(default)]
    pub implant: Option<ImplantSectionInput>,
}

/// Réponse de `PUT`/`GET /v1/cabinet/consultations/:id/cr`.
#[derive(Serialize)]
pub struct ConsultationCrResponse {
    pub template_id: Option<Uuid>,
    pub sections: Vec<CrSection>,
    pub status: String,
}

fn validate_sections(sections: &[CrSection]) -> Result<(), AppError> {
    if sections.len() > MAX_CR_SECTIONS {
        return Err(AppError::ValidationError);
    }
    for section in sections {
        if section.key.trim().is_empty() {
            return Err(AppError::ValidationError);
        }
        crate::text_validation::reject_nul_byte(&section.key)?;
        crate::text_validation::reject_nul_byte(&section.title)?;
        crate::text_validation::reject_nul_byte(&section.content)?;
        crate::text_validation::validate_max_len(&section.key, MAX_CR_SECTION_KEY_LEN)?;
        crate::text_validation::validate_max_len(&section.title, MAX_CR_SECTION_TITLE_LEN)?;
        crate::text_validation::validate_max_len(&section.content, MAX_CR_SECTION_CONTENT_LEN)?;
    }
    Ok(())
}

/// Stub chiffrement (`"STUB_ENC:"` + XOR 0xFF octet à octet, AES-256-GCM/KMS à
/// NUB-T3, ADR-009) — même schéma que `consultations::set_consultation_note`,
/// appliqué ici au JSON sérialisé des sections plutôt qu'à une note libre.
fn stub_encrypt_sections(sections: &[CrSection]) -> Result<Vec<u8>, AppError> {
    let json = serde_json::to_vec(sections).map_err(|_| AppError::Internal)?;
    let mut ciphertext: Vec<u8> = b"STUB_ENC:".to_vec();
    ciphertext.extend(json.iter().map(|b| b ^ 0xFF));
    Ok(ciphertext)
}

/// Inverse de [`stub_encrypt_sections`]. `[]` si le préfixe est absent ou le
/// contenu déchiffré non désérialisable (legacy/scaffold).
fn stub_decrypt_sections(ciphertext: &[u8]) -> Vec<CrSection> {
    let prefix = b"STUB_ENC:";
    let Some(payload) = ciphertext.strip_prefix(prefix.as_ref()) else {
        return Vec::new();
    };
    let plain: Vec<u8> = payload.iter().map(|b| b ^ 0xFF).collect();
    serde_json::from_slice(&plain).unwrap_or_default()
}

/// Charge la séance `session_id` et vérifie que `claims` en est le
/// praticien propriétaire (même garde que `consultations::set_consultation_note`).
/// Retourne `(appointment_id, patient_id, practitioner_id, session_status)`.
async fn load_owned_session(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    session_id: Uuid,
    claims: &ProPractitionerClaims,
) -> Result<(Uuid, Uuid, Uuid, String), AppError> {
    let session_row = sqlx::query(
        "SELECT cs.appointment_id, cs.practitioner_id, cs.status, a.patient_id \
         FROM consultation_session cs \
         JOIN appointment a ON a.id = cs.appointment_id \
         WHERE cs.id = $1 AND cs.cabinet_id = $2",
    )
    .bind(session_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let appointment_id: Uuid = session_row
        .try_get("appointment_id")
        .map_err(|_| AppError::Internal)?;
    let practitioner_id: Uuid = session_row
        .try_get("practitioner_id")
        .map_err(|_| AppError::Internal)?;
    let status: String = session_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    let patient_id: Uuid = session_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    let prac_row = sqlx::query(
        "SELECT id FROM practitioner WHERE id = $1 AND user_id = $2 AND cabinet_id = $3",
    )
    .bind(practitioner_id)
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    if prac_row.is_none() {
        return Err(AppError::Forbidden);
    }

    Ok((appointment_id, patient_id, practitioner_id, status))
}

/// Upsert de la section implant (#7154) dans `implant_passport`, idempotent
/// via `consultation_cr.implant_passport_id` : la première frappe qui
/// renseigne `brand`/`implant_ref` crée l'implant, les suivantes le mettent
/// à jour au lieu d'en créer un nouveau à chaque autosave.
async fn upsert_implant_section(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    cabinet_id: Uuid,
    patient_id: Uuid,
    cr_id: Uuid,
    existing_implant_passport_id: Option<Uuid>,
    implant: &ImplantSectionInput,
) -> Result<(), AppError> {
    let brand = implant.brand.trim().to_string();
    let implant_ref = implant.implant_ref.trim().to_string();
    if brand.is_empty() || implant_ref.is_empty() {
        return Ok(());
    }
    crate::text_validation::reject_nul_byte(&brand)?;
    crate::text_validation::reject_nul_byte(&implant_ref)?;
    if let Some(lot) = &implant.lot_number {
        crate::text_validation::reject_nul_byte(lot)?;
    }
    if let Some(tooth) = &implant.tooth_position {
        crate::text_validation::reject_nul_byte(tooth)?;
    }
    if let Some(notes) = &implant.notes {
        crate::text_validation::reject_nul_byte(notes)?;
    }
    let placement_date: Option<chrono::NaiveDate> = implant
        .placement_date
        .as_deref()
        .map(|s| s.parse::<chrono::NaiveDate>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;

    if let Some(implant_passport_id) = existing_implant_passport_id {
        sqlx::query(
            "UPDATE implant_passport \
             SET brand = $1, implant_ref = $2, lot_number = $3, placement_date = $4, \
                 tooth_position = $5, notes = $6 \
             WHERE id = $7 AND cabinet_id = $8",
        )
        .bind(&brand)
        .bind(&implant_ref)
        .bind(implant.lot_number.as_deref())
        .bind(placement_date)
        .bind(implant.tooth_position.as_deref())
        .bind(implant.notes.as_deref())
        .bind(implant_passport_id)
        .bind(cabinet_id)
        .execute(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
    } else {
        let row = sqlx::query(
            "INSERT INTO implant_passport \
             (cabinet_id, patient_id, implant_ref, brand, lot_number, placement_date, \
              tooth_position, notes) \
             VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
        )
        .bind(cabinet_id)
        .bind(patient_id)
        .bind(&implant_ref)
        .bind(&brand)
        .bind(implant.lot_number.as_deref())
        .bind(placement_date)
        .bind(implant.tooth_position.as_deref())
        .bind(implant.notes.as_deref())
        .fetch_one(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;
        let implant_passport_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

        sqlx::query("UPDATE consultation_cr SET implant_passport_id = $1 WHERE id = $2")
            .bind(implant_passport_id)
            .bind(cr_id)
            .execute(&mut **tx)
            .await
            .map_err(|_| AppError::Internal)?;
    }

    Ok(())
}

/// `PUT /v1/cabinet/consultations/:id/cr` — sauvegarde le brouillon du CR
/// structuré (#7154), appelé à chaque frappe côté front (idempotent).
///
/// Praticien uniquement (R.4127-72, §07 §4.1), propriétaire de la séance
/// (même garde que `set_consultation_note`) — sinon `403`. Séance
/// inexistante ou hors tenant → `404`. Séance `cancelled` → `409
/// invalid_status` (rien à documenter). CR déjà finalisé → `409
/// invalid_status` (finaliser fige le CR, pas de ré-édition dans ce
/// correctif). Une section
/// `implant` avec `brand`/`implant_ref` renseignés alimente
/// `implant_passport` (upsert idempotent, cf. [`upsert_implant_section`]).
pub async fn save_consultation_cr(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<SaveConsultationCrBody>,
) -> Result<Json<ConsultationCrResponse>, AppError> {
    validate_sections(&body.sections)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (appointment_id, patient_id, practitioner_id, session_status) =
        load_owned_session(&mut tx, id, &claims).await?;

    if session_status == "cancelled" {
        return Err(AppError::InvalidStatus);
    }

    let ciphertext = stub_encrypt_sections(&body.sections)?;

    let existing = sqlx::query(
        "SELECT id, status, implant_passport_id FROM consultation_cr WHERE appointment_id = $1",
    )
    .bind(appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let (cr_id, implant_passport_id) = match existing {
        Some(row) => {
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            if status == "finalized" {
                return Err(AppError::InvalidStatus);
            }
            let cr_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            let implant_passport_id: Option<Uuid> = row
                .try_get("implant_passport_id")
                .map_err(|_| AppError::Internal)?;

            sqlx::query(
                "UPDATE consultation_cr \
                 SET template_id = $1, sections_ciphertext = $2, sections_key_ref = 'stub-key-ref', \
                     updated_at = now() \
                 WHERE id = $3",
            )
            .bind(body.template_id)
            .bind(&ciphertext)
            .bind(cr_id)
            .execute(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

            (cr_id, implant_passport_id)
        }
        None => {
            let row = sqlx::query(
                "INSERT INTO consultation_cr \
                 (cabinet_id, appointment_id, practitioner_id, template_id, \
                  sections_ciphertext, sections_key_ref) \
                 VALUES ($1, $2, $3, $4, $5, 'stub-key-ref') RETURNING id",
            )
            .bind(claims.cabinet_id)
            .bind(appointment_id)
            .bind(practitioner_id)
            .bind(body.template_id)
            .bind(&ciphertext)
            .fetch_one(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
            let cr_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
            (cr_id, None)
        }
    };

    if let Some(implant) = &body.implant {
        upsert_implant_section(
            &mut tx,
            claims.cabinet_id,
            patient_id,
            cr_id,
            implant_passport_id,
            implant,
        )
        .await?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        "consultation cr draft saved"
    );

    Ok(Json(ConsultationCrResponse {
        template_id: body.template_id,
        sections: body.sections,
        status: "draft".to_string(),
    }))
}

// ── GET /v1/cabinet/consultations/:id/cr ──────────────────────────────────────

/// `GET /v1/cabinet/consultations/:id/cr` — relit le brouillon/CR finalisé
/// (#7154). Aucun CR structuré enregistré pour cette séance → sections
/// vides, `status: "draft"` (même convention que
/// `medical_record::get_medical_record` : objet par défaut plutôt que 404).
/// Mêmes gardes que `save_consultation_cr` (praticien propriétaire).
pub async fn get_consultation_cr(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationCrResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (appointment_id, _patient_id, _practitioner_id, _session_status) =
        load_owned_session(&mut tx, id, &claims).await?;

    let row = sqlx::query(
        "SELECT template_id, sections_ciphertext, status \
         FROM consultation_cr WHERE appointment_id = $1",
    )
    .bind(appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let response = match row {
        None => ConsultationCrResponse {
            template_id: None,
            sections: vec![],
            status: "draft".to_string(),
        },
        Some(row) => {
            let template_id: Option<Uuid> =
                row.try_get("template_id").map_err(|_| AppError::Internal)?;
            let ciphertext: Option<Vec<u8>> = row
                .try_get("sections_ciphertext")
                .map_err(|_| AppError::Internal)?;
            let status: String = row.try_get("status").map_err(|_| AppError::Internal)?;
            let sections = ciphertext
                .map(|c| stub_decrypt_sections(&c))
                .unwrap_or_default();
            ConsultationCrResponse {
                template_id,
                sections,
                status,
            }
        }
    };

    Ok(Json(response))
}

// ── POST /v1/cabinet/consultations/:id/cr/finalize ───────────────────────────

/// `POST /v1/cabinet/consultations/:id/cr/finalize` — fige le CR structuré
/// (#7154) et recopie son rendu texte dans `consultation_clinique` (compte
/// rendu patient, migration 0113 — même mécanisme que
/// `consultations::complete_consultation` pour la note libre).
///
/// Aucun brouillon enregistré, ou brouillon sans aucune section non vide →
/// `422 validation_error` (rien à finaliser). Déjà finalisé ou séance
/// `cancelled` → `409 invalid_status`.
pub async fn finalize_consultation_cr(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
) -> Result<Json<ConsultationCrResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (appointment_id, _patient_id, practitioner_id, session_status) =
        load_owned_session(&mut tx, id, &claims).await?;

    if session_status == "cancelled" {
        return Err(AppError::InvalidStatus);
    }

    let cr_row = sqlx::query(
        "SELECT id, template_id, sections_ciphertext, status \
         FROM consultation_cr WHERE appointment_id = $1",
    )
    .bind(appointment_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::ValidationError)?;

    let status: String = cr_row.try_get("status").map_err(|_| AppError::Internal)?;
    if status == "finalized" {
        return Err(AppError::InvalidStatus);
    }
    let cr_id: Uuid = cr_row.try_get("id").map_err(|_| AppError::Internal)?;
    let template_id: Option<Uuid> = cr_row
        .try_get("template_id")
        .map_err(|_| AppError::Internal)?;
    let ciphertext: Option<Vec<u8>> = cr_row
        .try_get("sections_ciphertext")
        .map_err(|_| AppError::Internal)?;
    let sections = ciphertext
        .map(|c| stub_decrypt_sections(&c))
        .unwrap_or_default();

    if !sections.iter().any(|s| !s.content.trim().is_empty()) {
        return Err(AppError::ValidationError);
    }

    sqlx::query(
        "UPDATE consultation_cr SET status = 'finalized', updated_at = now() WHERE id = $1",
    )
    .bind(cr_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let rendered_text = render_sections_text(&sections);
    let mut clinique_ciphertext: Vec<u8> = b"STUB_ENC:".to_vec();
    clinique_ciphertext.extend(rendered_text.as_bytes().iter().map(|b| b ^ 0xFF));

    // Même mécanisme que `complete_consultation` (#6234) : ON CONFLICT sur
    // `appointment_id` (contrainte UNIQUE), idempotent si un compte rendu
    // (issu de la note libre ou d'une précédente finalisation) existe déjà.
    sqlx::query(
        "INSERT INTO consultation_clinique \
         (cabinet_id, appointment_id, practitioner_id, content_ciphertext, \
          content_key_ref, status) \
         VALUES ($1, $2, $3, $4, 'stub-key-ref', 'finalized') \
         ON CONFLICT (appointment_id) DO UPDATE \
         SET content_ciphertext = EXCLUDED.content_ciphertext, \
             content_key_ref = EXCLUDED.content_key_ref, \
             status = 'finalized', \
             updated_at = now()",
    )
    .bind(claims.cabinet_id)
    .bind(appointment_id)
    .bind(practitioner_id)
    .bind(&clinique_ciphertext)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        consultation_id = %id,
        "consultation cr finalized"
    );

    Ok(Json(ConsultationCrResponse {
        template_id,
        sections,
        status: "finalized".to_string(),
    }))
}

// ── GET /v1/cabinet/consultations/:id/cr/render ──────────────────────────────

/// Query de `GET /v1/cabinet/consultations/:id/cr/render`.
#[derive(Deserialize)]
pub struct RenderConsultationCrQuery {
    #[serde(default)]
    pub format: Option<String>,
}

fn render_sections_text(sections: &[CrSection]) -> String {
    let mut text = String::new();
    for section in sections {
        if !text.is_empty() {
            text.push_str("\n\n");
        }
        text.push_str(&section.title);
        text.push('\n');
        text.push_str(&section.content);
    }
    text
}

/// Génère le contenu binaire (PDF minimal valide) du CR structuré — même
/// approche que `implant_passport.rs::render_implant_passport_pdf` (pas de
/// dépendance externe, structure `%PDF-1.4` minimale). Encodage
/// `/WinAnsiEncoding` mono-octet via `escape_winansi` (#7117/#7125) — sinon
/// tout caractère accentué est rendu en mojibake par un lecteur PDF.
fn render_consultation_cr_pdf(patient_name: &str, sections: &[CrSection]) -> Vec<u8> {
    let mut lines: Vec<String> = vec![
        "Compte rendu de consultation".to_string(),
        format!("Patient : {}", patient_name),
        String::new(),
    ];
    if sections.is_empty() || sections.iter().all(|s| s.content.trim().is_empty()) {
        lines.push("Aucune section renseignee.".to_string());
    }
    for section in sections {
        if section.content.trim().is_empty() {
            continue;
        }
        lines.push(format!("{} :", section.title));
        for content_line in section.content.lines() {
            lines.push(content_line.to_string());
        }
        lines.push(String::new());
    }

    let mut content: Vec<u8> = b"BT /F1 12 Tf 50 780 Td 14 TL\n".to_vec();
    for line in &lines {
        content.push(b'(');
        content.extend(crate::prescriptions::escape_winansi(line));
        content.extend_from_slice(b") Tj T*\n");
    }
    content.extend_from_slice(b"ET");

    let objects: Vec<Vec<u8>> = vec![
        b"<< /Type /Catalog /Pages 2 0 R >>".to_vec(),
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_vec(),
        b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> \
         /MediaBox [0 0 595 842] /Contents 4 0 R >>"
            .to_vec(),
        {
            let mut obj = format!("<< /Length {} >>\nstream\n", content.len()).into_bytes();
            obj.extend_from_slice(&content);
            obj.extend_from_slice(b"\nendstream");
            obj
        },
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"
            .to_vec(),
    ];

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

/// `GET /v1/cabinet/consultations/:id/cr/render?format=text|pdf` — rend le
/// CR structuré (brouillon ou finalisé) en texte brut (défaut) ou en PDF
/// (#7154). `format` hors `{text, pdf}` → `422`. Mêmes gardes que
/// `get_consultation_cr` (praticien propriétaire de la séance).
pub async fn render_consultation_cr(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Query(query): Query<RenderConsultationCrQuery>,
) -> Result<Response, AppError> {
    let format = query.format.as_deref().unwrap_or("text");
    if !matches!(format, "text" | "pdf") {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (appointment_id, patient_id, _practitioner_id, _session_status) =
        load_owned_session(&mut tx, id, &claims).await?;

    let cr_row =
        sqlx::query("SELECT sections_ciphertext FROM consultation_cr WHERE appointment_id = $1")
            .bind(appointment_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let patient_row = sqlx::query("SELECT first_name, last_name FROM patient WHERE id = $1")
        .bind(patient_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let sections: Vec<CrSection> = cr_row
        .and_then(|row| {
            row.try_get::<Option<Vec<u8>>, _>("sections_ciphertext")
                .ok()
                .flatten()
        })
        .map(|c| stub_decrypt_sections(&c))
        .unwrap_or_default();

    let patient_name = match patient_row {
        Some(row) => {
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            format!("{} {}", first_name, last_name)
        }
        None => patient_id.to_string(),
    };

    if format == "pdf" {
        let pdf = render_consultation_cr_pdf(&patient_name, &sections);
        Ok((
            StatusCode::OK,
            [
                (
                    header::CONTENT_TYPE,
                    HeaderValue::from_static("application/pdf"),
                ),
                (
                    header::CONTENT_DISPOSITION,
                    HeaderValue::from_static("inline; filename=\"compte-rendu.pdf\""),
                ),
            ],
            pdf,
        )
            .into_response())
    } else {
        let text = render_sections_text(&sections);
        Ok((
            StatusCode::OK,
            [(
                header::CONTENT_TYPE,
                HeaderValue::from_static("text/plain; charset=utf-8"),
            )],
            text,
        )
            .into_response())
    }
}
