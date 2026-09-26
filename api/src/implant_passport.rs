//! Handlers `GET /v1/implant-passport`, `GET /v1/implant-passport/export`
//! (lecture patient) et `POST /v1/cabinet/patients/:id/implants` (écriture
//! praticien, #4140) — passeport implantaire.

use std::sync::Arc;

use axum::body::Body;
use axum::extract::{Extension, Path, Query, State};
use axum::http::{header, StatusCode};
use axum::response::Response;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, PatientAccountClaims, ProPractitionerClaims},
    AppState, ObjectStorage, StorageSigner,
};

/// Un implant du passeport implantaire patient.
#[derive(Serialize)]
pub struct ImplantItem {
    pub id: Uuid,
    pub brand: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lot_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub placement_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth_position: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
    // Identification dispositif + suivi (#7665) — distincts de `brand`/
    // `lot_number`, données demandées par un radiologue avant imagerie
    // (matériau, compatibilité IRM, dimensions) et suivi périodique.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub manufacturer: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub model: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reference: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub dimensions: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub material: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub mri_compatibility: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_control_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub next_control: Option<String>,
}

/// Réponse de `GET /v1/implant-passport`.
#[derive(Serialize)]
pub struct ImplantPassportResponse {
    pub data: Vec<ImplantItem>,
}

fn implant_item_from_row(row: &sqlx::postgres::PgRow) -> Result<ImplantItem, AppError> {
    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let brand: String = row.try_get("brand").map_err(|_| AppError::Internal)?;
    let lot_number: Option<String> = row.try_get("lot_number").map_err(|_| AppError::Internal)?;
    let placement_date: Option<chrono::NaiveDate> = row
        .try_get("placement_date")
        .map_err(|_| AppError::Internal)?;
    let tooth_position: Option<String> = row
        .try_get("tooth_position")
        .map_err(|_| AppError::Internal)?;
    let notes: Option<String> = row.try_get("notes").map_err(|_| AppError::Internal)?;
    let manufacturer: Option<String> = row
        .try_get("manufacturer")
        .map_err(|_| AppError::Internal)?;
    let model: Option<String> = row.try_get("model").map_err(|_| AppError::Internal)?;
    let reference: Option<String> = row.try_get("reference").map_err(|_| AppError::Internal)?;
    let dimensions: Option<String> = row.try_get("dimensions").map_err(|_| AppError::Internal)?;
    let material: Option<String> = row.try_get("material").map_err(|_| AppError::Internal)?;
    let mri_compatibility: Option<String> = row
        .try_get("mri_compatibility")
        .map_err(|_| AppError::Internal)?;
    let last_control_date: Option<chrono::NaiveDate> = row
        .try_get("last_control_date")
        .map_err(|_| AppError::Internal)?;
    let next_control: Option<String> = row
        .try_get("next_control")
        .map_err(|_| AppError::Internal)?;

    Ok(ImplantItem {
        id,
        brand,
        lot_number,
        placement_date: placement_date.map(|d| d.to_string()),
        tooth_position,
        notes,
        manufacturer,
        model,
        reference,
        dimensions,
        material,
        mri_compatibility,
        last_control_date: last_control_date.map(|d| d.to_string()),
        next_control,
    })
}

/// `GET /v1/implant-passport` — liste les implants dentaires du patient authentifié.
///
/// Token `kind:"patient"` requis. RLS via `app.patient_account_id` (migration 0077),
/// étendue à la branche tutelle (migration 0219, #4641).
/// Lecture seule — données non chiffrées (pas de PII directe).
/// Aucun implant → `{ data: [] }`.
pub async fn list_implant_passport(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
) -> Result<Json<ImplantPassportResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS implant_passport_patient_read (migration 0077).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    // Requis pour la branche tutelle de implant_passport_patient_read
    // (migration 0219, account_guardianship RLS) — cf. appointment_patient_read (0196).
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, brand, lot_number, placement_date, tooth_position, notes, \
         manufacturer, model, reference, dimensions, material, mri_compatibility, \
         last_control_date, next_control \
         FROM implant_passport \
         WHERE deleted_at IS NULL \
         ORDER BY placement_date DESC NULLS LAST, id DESC",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<ImplantItem> = Vec::with_capacity(rows.len());
    for row in &rows {
        data.push(implant_item_from_row(row)?);
    }

    tracing::info!(
        account_id = %claims.account_id,
        count = data.len(),
        "implant passport listed"
    );

    Ok(Json(ImplantPassportResponse { data }))
}

/// Query params de `GET /v1/implant-passport/export`.
#[derive(Deserialize)]
pub struct ExportImplantPassportQuery {
    /// Limite l'export à cet implant seul (#5334) — évite de transmettre
    /// tout l'historique pour un partage ciblé. Absent → export du
    /// passeport complet (comportement historique, #4142).
    #[serde(default)]
    pub implant_id: Option<Uuid>,
}

/// `GET /v1/implant-passport/export` — export PDF du passeport implantaire.
///
/// Token `kind:"patient"` requis. Génère le PDF puis l'uploade dans l'Object
/// Storage (#6461 — remplace le stub qui ne faisait que signer une clé jamais
/// écrite, cf. #4626) avant de retourner `302 Found` avec `Location` vers
/// l'URL signée. Échec du signer → `502 upstream_unavailable`. Aucun implant
/// présent → ne bloque pas l'export (le PDF généré liste alors qu'aucun
/// implant n'est enregistré).
/// `?implant_id=` (#5334) scope l'export à un implant : l'implant doit
/// appartenir au compte authentifié (RLS `implant_passport_patient_read`,
/// migration 0077/0219) sinon `404`.
pub async fn export_implant_passport(
    State(state): State<AppState>,
    claims: PatientAccountClaims,
    Extension(signer): Extension<Arc<dyn StorageSigner>>,
    Extension(object_storage): Extension<Arc<dyn ObjectStorage>>,
    Query(query): Query<ExportImplantPassportQuery>,
) -> Result<Response, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    // Scope patient — RLS implant_passport_patient_read (migration 0077/0219).
    sqlx::query("SELECT set_config('app.patient_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    sqlx::query("SELECT set_config('app.current_account_id', $1, true)")
        .bind(claims.account_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let (storage_key, items) = if let Some(implant_id) = query.implant_id {
        let row = sqlx::query(
            "SELECT id, brand, lot_number, placement_date, tooth_position, notes, \
             manufacturer, model, reference, dimensions, material, mri_compatibility, \
             last_control_date, next_control \
             FROM implant_passport WHERE id = $1 AND deleted_at IS NULL",
        )
        .bind(implant_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

        (
            format!("implant-passport/{}/{}.pdf", claims.account_id, implant_id),
            vec![implant_item_from_row(&row)?],
        )
    } else {
        let rows = sqlx::query(
            "SELECT id, brand, lot_number, placement_date, tooth_position, notes, \
             manufacturer, model, reference, dimensions, material, mri_compatibility, \
             last_control_date, next_control \
             FROM implant_passport \
             WHERE deleted_at IS NULL \
             ORDER BY placement_date DESC NULLS LAST, id DESC",
        )
        .fetch_all(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

        let mut items: Vec<ImplantItem> = Vec::with_capacity(rows.len());
        for row in &rows {
            items.push(implant_item_from_row(row)?);
        }

        (format!("implant-passport/{}.pdf", claims.account_id), items)
    };

    // Nom du porteur affiché sur le PDF (#7227) — plutôt que l'UUID technique
    // du compte, cf. `patient_name` de `render_prescription_pdf`
    // (`prescriptions.rs:422`). `app.current_account_id` est déjà posé
    // ci-dessus au compte authentifié (lecture de sa propre fiche).
    // `fetch_optional` (pas `fetch_one`) : repli sur l'identifiant technique
    // dans le cas dégénéré où le token ne référence aucune fiche `patient_account`
    // — ne doit jamais se produire en production (un token patient suppose un
    // compte déjà créé), mais évite un 500 plutôt qu'un simple manque d'affichage.
    let account_row =
        sqlx::query("SELECT first_name, last_name FROM patient_account WHERE id = $1")
            .bind(claims.account_id)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let patient_name = match account_row {
        Some(row) => {
            let first_name: String = row.try_get("first_name").map_err(|_| AppError::Internal)?;
            let last_name: String = row.try_get("last_name").map_err(|_| AppError::Internal)?;
            format!("{} {}", first_name, last_name)
        }
        None => claims.account_id.to_string(),
    };

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Génère le PDF (contenu réel) puis l'uploade dans l'Object Storage via
    // le client injecté (Postgres en prod, in-memory en test) — `storage_key`
    // référence désormais un objet effectivement écrit, plus une clé fantôme
    // (#6461, même correctif que `sign_prescription`/#4626).
    let pdf_bytes = render_implant_passport_pdf(&patient_name, &items);
    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes)
        .await
        .map_err(|_| AppError::Internal)?;

    // `signer.sign() == None` : le lien n'a jamais été généré (signer non
    // configuré), pas "expiré" — 502 upstream_unavailable, pas 410 link_expired
    // (aligne sur le contrat #4835, cf. documents.rs).
    let signed_url = signer
        .sign(&storage_key)
        .ok_or(AppError::UpstreamUnavailable)?;

    tracing::info!(
        account_id = %claims.account_id,
        implant_id = ?query.implant_id,
        "implant passport export redirected"
    );

    Response::builder()
        .status(StatusCode::FOUND)
        .header(header::LOCATION, &signed_url)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Body::empty())
        .map_err(|_| AppError::Internal)
}

/// Convertit une date ISO (`YYYY-MM-DD`, format de `ImplantItem::placement_date`,
/// cf. `NaiveDate::to_string()` en `:58`) en date lisible `JJ/MM/AAAA` pour
/// l'affichage PDF (#7227, même contrat que `format_paris_date` de
/// `scheduling.rs` pour les deux autres générateurs — sans conversion de fuseau
/// horaire ici, `placement_date` étant une date calendaire pure, pas un instant UTC).
fn format_placement_date_fr(iso_date: &str) -> String {
    chrono::NaiveDate::parse_from_str(iso_date, "%Y-%m-%d")
        .map(|d| d.format("%d/%m/%Y").to_string())
        .unwrap_or_else(|_| iso_date.to_string())
}

/// Génère le contenu binaire (PDF minimal valide) du passeport implantaire.
///
/// Même approche que `render_prescription_pdf` (`prescriptions.rs`) : pas de
/// dépendance externe (crate PDF), structure `%PDF-1.4` minimale suffisante
/// pour obtenir un document ouvrable par n'importe quel lecteur, avec un
/// contenu réel et non nul. Encodage `/WinAnsiEncoding` mono-octet via
/// `escape_winansi` (#7117/#7125) — sinon tout caractère accentué (marque,
/// référence, lot du dispositif) est rendu en mojibake par un lecteur PDF.
fn render_implant_passport_pdf(patient_name: &str, items: &[ImplantItem]) -> Vec<u8> {
    let mut lines: Vec<String> = vec![
        "Passeport implantaire".to_string(),
        format!("Patient : {}", patient_name),
        String::new(),
    ];
    if items.is_empty() {
        lines.push("Aucun implant enregistre.".to_string());
    }
    for item in items {
        let mut line = item.brand.clone();
        if let Some(tooth_position) = &item.tooth_position {
            line.push_str(&format!(" ({})", tooth_position));
        }
        if let Some(placement_date) = &item.placement_date {
            line.push_str(&format!(
                " - Pose le {}",
                format_placement_date_fr(placement_date)
            ));
        }
        if let Some(lot_number) = &item.lot_number {
            line.push_str(&format!(" - Lot {}", lot_number));
        }
        lines.push(line);
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

// ── GET /v1/cabinet/patients/:id/implants ──────────────────────────────────

/// Un implant du passeport implantaire, vue cabinet (avec `implant_ref`,
/// traçabilité médico-légale — jamais restitué côté patient, cf. #4830).
#[derive(Serialize)]
pub struct CabinetImplantItem {
    pub id: Uuid,
    pub brand: String,
    pub implant_ref: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lot_number: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub placement_date: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tooth_position: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub notes: Option<String>,
}

/// Réponse de `GET /v1/cabinet/patients/:id/implants`.
#[derive(Serialize)]
pub struct CabinetImplantPassportResponse {
    pub data: Vec<CabinetImplantItem>,
}

/// `GET /v1/cabinet/patients/:id/implants` — liste les implants posés à un
/// patient, vue cabinet (#4830).
///
/// Praticien uniquement (`ProPractitionerClaims`). `patient_id` (path)
/// inexistant ou hors tenant → `404`. Garde §14 (relation de soin, même
/// pattern que `create_implant`/`prescription_list.rs`) : praticien sans
/// `appointment` avec ce patient → `403`. Contrairement à
/// `GET /v1/implant-passport` (vue patient), inclut `implant_ref` —
/// traçabilité dispositif médical (rappel de lot) requise à la saisie mais
/// jamais restituée avant ce correctif.
pub async fn list_cabinet_implants(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
) -> Result<Json<CabinetImplantPassportResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Garde §14 (relation de soin) — même pattern que create_implant.
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let rows = sqlx::query(
        "SELECT id, brand, implant_ref, lot_number, placement_date, tooth_position, notes \
         FROM implant_passport \
         WHERE patient_id = $1 AND cabinet_id = $2 AND deleted_at IS NULL \
         ORDER BY placement_date DESC NULLS LAST, id DESC",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut data: Vec<CabinetImplantItem> = Vec::with_capacity(rows.len());
    for row in rows {
        let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
        let brand: String = row.try_get("brand").map_err(|_| AppError::Internal)?;
        let implant_ref: String = row.try_get("implant_ref").map_err(|_| AppError::Internal)?;
        let lot_number: Option<String> =
            row.try_get("lot_number").map_err(|_| AppError::Internal)?;
        let placement_date: Option<chrono::NaiveDate> = row
            .try_get("placement_date")
            .map_err(|_| AppError::Internal)?;
        let tooth_position: Option<String> = row
            .try_get("tooth_position")
            .map_err(|_| AppError::Internal)?;
        let notes: Option<String> = row.try_get("notes").map_err(|_| AppError::Internal)?;

        data.push(CabinetImplantItem {
            id,
            brand,
            implant_ref,
            lot_number,
            placement_date: placement_date.map(|d| d.to_string()),
            tooth_position,
            notes,
        });
    }

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        patient_id = %patient_id,
        count = data.len(),
        "cabinet implants listed"
    );

    Ok(Json(CabinetImplantPassportResponse { data }))
}

/// Valide un code dent ISO 3950 (notation FDI) : `<quadrant><dent>`,
/// quadrant 1-4 (dentition permanente, dents 1-8) ou 5-8 (temporaire, 1-5).
/// Même règle que `dental_chart.rs::validate_teeth`/`treatment_phases.rs::is_valid_fdi_tooth`
/// (#3680) — dupliquée ici faute de module de validation partagé.
fn is_valid_fdi_tooth(code: &str) -> bool {
    code.len() == 2 && code.chars().all(|c| c.is_ascii_digit()) && {
        let quadrant = code.as_bytes()[0] - b'0';
        let tooth = code.as_bytes()[1] - b'0';
        match quadrant {
            1..=4 => (1..=8).contains(&tooth),
            5..=8 => (1..=5).contains(&tooth),
            _ => false,
        }
    }
}

// ── POST /v1/cabinet/patients/:id/implants ────────────────────────────────

/// Corps de `POST /v1/cabinet/patients/:id/implants`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateImplantBody {
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

/// Réponse de `POST /v1/cabinet/patients/:id/implants`.
#[derive(Serialize)]
pub struct CreateImplantResponse {
    pub implant_id: Uuid,
}

/// `POST /v1/cabinet/patients/:id/implants` — enregistre un implant posé (#4140).
///
/// Praticien uniquement (`ProPractitionerClaims`) — `cabinet_id` extrait du
/// JWT, jamais du body (invariant tenancy). `patient_id` (path) inexistant ou
/// hors tenant → `404`. Garde §14 (relation de soin, même pattern que
/// `prescriptions.rs::create_prescription`/`dental_chart.rs`) : praticien
/// sans `appointment` avec ce patient dans ce cabinet → `403`. `brand`/
/// `implant_ref` vides → `422`. `placement_date` dans le futur ou antérieure
/// à 120 ans → `422` (#7743). `tooth_position` hors numérotation ISO 3950,
/// comme `dental-chart` → `422` (#6994). Visible ensuite côté patient via
/// `GET /v1/implant-passport`.
pub async fn create_implant(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<CreateImplantBody>,
) -> Result<(StatusCode, Json<CreateImplantResponse>), AppError> {
    let brand = body.brand.trim().to_string();
    let implant_ref = body.implant_ref.trim().to_string();
    if brand.is_empty() || implant_ref.is_empty() {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(&brand)?;
    crate::text_validation::reject_nul_byte(&implant_ref)?;
    if let Some(lot) = &body.lot_number {
        crate::text_validation::reject_nul_byte(lot)?;
    }
    if let Some(tooth) = &body.tooth_position {
        crate::text_validation::reject_nul_byte(tooth)?;
        if !is_valid_fdi_tooth(tooth) {
            return Err(AppError::ValidationError);
        }
    }
    if let Some(notes) = &body.notes {
        crate::text_validation::reject_nul_byte(notes)?;
    }
    let placement_date: Option<chrono::NaiveDate> = body
        .placement_date
        .as_deref()
        .map(|s| s.parse::<chrono::NaiveDate>())
        .transpose()
        .map_err(|_| AppError::ValidationError)?;
    if let Some(d) = placement_date {
        let today = chrono::Utc::now().date_naive();
        // Borne basse symétrique à la borne haute (#7743) : même fenêtre que
        // la date de naissance (#6653) — 120 ans dans le passé, jamais dans
        // le futur (on ne pose pas un implant demain).
        let min_placement_date = today
            .checked_sub_months(chrono::Months::new(120 * 12))
            .ok_or(AppError::ValidationError)?;
        if d > today || d < min_placement_date {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let patient_exists = sqlx::query(
        "SELECT 1 FROM patient WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if patient_exists.is_none() {
        return Err(AppError::NotFound);
    }

    // Garde §14 (relation de soin) — même pattern que
    // prescriptions.rs/dental_chart.rs/periodontal_chart.rs.
    let has_appointment = sqlx::query(
        "SELECT 1 FROM appointment a \
         JOIN practitioner p ON p.id = a.practitioner_id \
         WHERE a.patient_id = $1 AND a.cabinet_id = $2 \
           AND p.user_id = $3 AND a.deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    if has_appointment.is_none() {
        return Err(AppError::Forbidden);
    }

    let implant_row = sqlx::query(
        "INSERT INTO implant_passport \
         (cabinet_id, patient_id, implant_ref, brand, lot_number, placement_date, tooth_position, notes) \
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&implant_ref)
    .bind(&brand)
    .bind(body.lot_number.as_deref())
    .bind(placement_date)
    .bind(body.tooth_position.as_deref())
    .bind(body.notes.as_deref())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let implant_id: Uuid = implant_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        implant_id = %implant_id,
        "implant created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateImplantResponse { implant_id }),
    ))
}
