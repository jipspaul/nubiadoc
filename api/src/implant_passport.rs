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

    Ok(ImplantItem {
        id,
        brand,
        lot_number,
        placement_date: placement_date.map(|d| d.to_string()),
        tooth_position,
        notes,
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
        "SELECT id, brand, lot_number, placement_date, tooth_position, notes \
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
            "SELECT id, brand, lot_number, placement_date, tooth_position, notes \
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
            "SELECT id, brand, lot_number, placement_date, tooth_position, notes \
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

    tx.commit().await.map_err(|_| AppError::Internal)?;

    // Génère le PDF (contenu réel) puis l'uploade dans l'Object Storage via
    // le client injecté (Postgres en prod, in-memory en test) — `storage_key`
    // référence désormais un objet effectivement écrit, plus une clé fantôme
    // (#6461, même correctif que `sign_prescription`/#4626).
    let pdf_bytes = render_implant_passport_pdf(claims.account_id, &items);
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

/// Génère le contenu binaire (PDF minimal valide) du passeport implantaire.
///
/// Même approche que `render_prescription_pdf` (`prescriptions.rs`) : pas de
/// dépendance externe (crate PDF), structure `%PDF-1.4` minimale suffisante
/// pour obtenir un document ouvrable par n'importe quel lecteur, avec un
/// contenu réel et non nul.
fn render_implant_passport_pdf(account_id: Uuid, items: &[ImplantItem]) -> Vec<u8> {
    let escape = |s: &str| {
        s.replace('\\', "\\\\")
            .replace('(', "\\(")
            .replace(')', "\\)")
    };

    let mut lines: Vec<String> = vec![
        "Passeport implantaire".to_string(),
        format!("Compte patient : {}", account_id),
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
            line.push_str(&format!(" - Pose le {}", placement_date));
        }
        if let Some(lot_number) = &item.lot_number {
            line.push_str(&format!(" - Lot {}", lot_number));
        }
        lines.push(line);
    }

    let mut content = String::from("BT /F1 12 Tf 50 780 Td 14 TL\n");
    for line in &lines {
        content.push_str(&format!("({}) Tj T*\n", escape(line)));
    }
    content.push_str("ET");

    let objects = [
        "<< /Type /Catalog /Pages 2 0 R >>".to_string(),
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>".to_string(),
        "<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R >> >> \
         /MediaBox [0 0 595 842] /Contents 4 0 R >>"
            .to_string(),
        format!(
            "<< /Length {} >>\nstream\n{}\nendstream",
            content.len(),
            content
        ),
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>".to_string(),
    ];

    let mut pdf = String::from("%PDF-1.4\n");
    let mut offsets = Vec::with_capacity(objects.len());
    for (i, obj) in objects.iter().enumerate() {
        offsets.push(pdf.len());
        pdf.push_str(&format!("{} 0 obj\n{}\nendobj\n", i + 1, obj));
    }
    let xref_offset = pdf.len();
    pdf.push_str(&format!("xref\n0 {}\n", objects.len() + 1));
    pdf.push_str("0000000000 65535 f \n");
    for off in &offsets {
        pdf.push_str(&format!("{:010} 00000 n \n", off));
    }
    pdf.push_str(&format!(
        "trailer\n<< /Size {} /Root 1 0 R >>\nstartxref\n{}\n%%EOF",
        objects.len() + 1,
        xref_offset
    ));

    pdf.into_bytes()
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

// ── POST /v1/cabinet/patients/:id/implants ────────────────────────────────

/// Corps de `POST /v1/cabinet/patients/:id/implants`.
#[derive(Deserialize)]
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
/// `implant_ref` vides → `422`. Visible ensuite côté patient via
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
