//! Handlers `consent_template` (#7199, DP-F6.b) : `GET`/`POST
//! /v1/cabinet/consent-templates`, `PATCH /v1/cabinet/consent-templates/:id`
//! et `POST /v1/consent-templates/:id/render`.
//!
//! S'appuie sur `consent_template` (migration 0279, #7200) : catalogue
//! global seedé (`cabinet_id IS NULL`) + variantes propres au cabinet, même
//! modèle RLS (`tenant_isolation` + `global_template_read`) que
//! `prescription_template`/`letter_template` — cf. `prescription_templates.rs`.
//!
//! `PATCH` ne modifie JAMAIS un modèle en place (cf. commentaire de la
//! migration 0279) : il désactive la version courante (`is_active = false`)
//! et insère une nouvelle ligne (`version + 1`) — un `consent_record` déjà
//! signé référence le texte exact qui a été présenté au patient, jamais
//! réécrit rétroactivement. La réponse porte donc un `id` NEUF, distinct de
//! celui passé dans l'URL.
//!
//! `render_consent_template` matérialise un modèle en document PDF pour un
//! patient et un devis donnés : nom/prénom du patient, dents et actes du
//! devis sont substitués dans les placeholders `{{patient.nom}}`,
//! `{{patient.prenom}}`, `{{dents}}`, `{{actes}}` s'ils apparaissent dans le
//! corps (le catalogue seedé n'en contient aucun), et systématiquement
//! résumés dans un bloc d'identification en tête du document — les modèles
//! du catalogue sont un texte juridique générique, pas paramétré par
//! placeholder. PDF texte produit par `pdf_text` (même mécanique que
//! `letters.rs`), stocké comme `document.category = 'consentement'` —
//! joignable au devis via `POST /v1/cabinet/quotes/:id/attachments`
//! (`kind: "consent"`, #7203/DP-F5.b), pas fait ici : cette route ne fait
//! que produire le document.

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    pdf_text,
    permissions::ProBillingClaims,
    text_validation, AppState, ObjectStorage,
};

/// Catégories d'acte (CHECK `consent_template_act_category_check`, migration 0279).
const VALID_ACT_CATEGORIES: &[&str] = &[
    "chirurgie_orale",
    "parodontologie",
    "implantologie",
    "prothese_amovible_partielle",
    "prothese_amovible_totale",
    "prothese_fixe_unitaire",
    "prothese_fixe_plurale",
    "orthodontie",
    "pedodontie",
    "endodontie",
];

/// Plafond métier (même doctrine que `cr_templates::MAX_CR_TEMPLATE_TITLE_LEN`, #7226).
const MAX_TITLE_LEN: usize = 200;
/// Plafond métier (même doctrine que `letters::MAX_BODY_CHARS`).
const MAX_BODY_LEN: usize = 20_000;

fn validate_act_category(act_category: &str) -> Result<(), AppError> {
    if VALID_ACT_CATEGORIES.contains(&act_category) {
        Ok(())
    } else {
        Err(AppError::ValidationError)
    }
}

// ── GET /v1/cabinet/consent-templates ────────────────────────────────────────

/// Un modèle de consentement, vu du cabinet courant.
#[derive(Serialize)]
pub struct ConsentTemplateDto {
    pub id: Uuid,
    pub act_category: String,
    pub title: String,
    pub body_markdown: String,
    pub version: i32,
    /// `true` : modèle global seedé (`cabinet_id IS NULL`), lecture seule.
    pub is_global: bool,
    pub created_at: String,
}

/// `GET /v1/cabinet/consent-templates` — liste les modèles actifs visibles
/// (catalogue global + modèles propres au cabinet).
///
/// Praticien uniquement. RLS scopée via `app.current_cabinet_id`
/// (`tenant_isolation` OR `global_template_read`). Seules les versions
/// actives (`is_active = true`) sont listées — une version désactivée par
/// `PATCH` reste en base pour l'historique mais n'est plus proposée.
pub async fn list_consent_templates(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<Vec<ConsentTemplateDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, act_category, title, body_markdown, version, \
                (cabinet_id IS NULL) AS is_global, created_at \
         FROM consent_template \
         WHERE is_active = true \
         ORDER BY (cabinet_id IS NULL) DESC, act_category, title",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut templates = Vec::with_capacity(rows.len());
    for row in &rows {
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        templates.push(ConsentTemplateDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            act_category: row
                .try_get("act_category")
                .map_err(|_| AppError::Internal)?,
            title: row.try_get("title").map_err(|_| AppError::Internal)?,
            body_markdown: row
                .try_get("body_markdown")
                .map_err(|_| AppError::Internal)?,
            version: row.try_get("version").map_err(|_| AppError::Internal)?,
            is_global: row.try_get("is_global").map_err(|_| AppError::Internal)?,
            created_at: created_at.to_rfc3339(),
        });
    }

    Ok(Json(templates))
}

// ── POST /v1/cabinet/consent-templates ───────────────────────────────────────

/// Corps de `POST /v1/cabinet/consent-templates`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateConsentTemplateBody {
    pub act_category: String,
    pub title: String,
    pub body_markdown: String,
}

/// Réponse de `POST`/`PATCH /v1/cabinet/consent-templates`.
#[derive(Serialize)]
pub struct ConsentTemplateIdResponse {
    pub id: Uuid,
    pub version: i32,
}

/// `POST /v1/cabinet/consent-templates` — crée un modèle propre au cabinet.
///
/// `act_category` doit être dans le catalogue de types d'acte → `422` sinon
/// (pré-vérifié, plutôt que de laisser remonter la violation CHECK en
/// `500`). `title`/`body_markdown` non vides/blancs et bornés → `422` sinon.
/// `cabinet_id` toujours celui du JWT (jamais `NULL`, cf. RLS
/// `global_template_read` : seule une migration crée un modèle global).
pub async fn create_consent_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreateConsentTemplateBody>,
) -> Result<(StatusCode, Json<ConsentTemplateIdResponse>), AppError> {
    validate_act_category(&body.act_category)?;
    if body.title.trim().is_empty() || body.body_markdown.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    text_validation::reject_nul_byte(&body.title)?;
    text_validation::reject_nul_byte(&body.body_markdown)?;
    text_validation::validate_max_len(&body.title, MAX_TITLE_LEN)?;
    text_validation::validate_max_len(&body.body_markdown, MAX_BODY_LEN)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO consent_template (cabinet_id, act_category, title, body_markdown) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id, version",
    )
    .bind(claims.cabinet_id)
    .bind(&body.act_category)
    .bind(body.title.trim())
    .bind(body.body_markdown.trim())
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;
    let version: i32 = row.try_get("version").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %id,
        act_category = %body.act_category,
        "consent template created"
    );

    Ok((
        StatusCode::CREATED,
        Json(ConsentTemplateIdResponse { id, version }),
    ))
}

// ── PATCH /v1/cabinet/consent-templates/:id ──────────────────────────────────

/// Corps de `PATCH /v1/cabinet/consent-templates/:id`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PatchConsentTemplateBody {
    pub act_category: Option<String>,
    pub title: Option<String>,
    pub body_markdown: Option<String>,
}

/// `PATCH /v1/cabinet/consent-templates/:id` — fait évoluer un modèle du
/// cabinet.
///
/// Champs absents = inchangés (même convention que `cr_templates::patch_cr_template`).
/// Modèle absent, hors tenant, ou global (`cabinet_id IS NULL`, RLS ne
/// couvre pas son `UPDATE`/lecture-écriture applicative ici) → `404`.
/// N'édite jamais la ligne existante : désactive la version courante
/// (`is_active = false`) et insère une nouvelle ligne `version + 1` — voir
/// doc de module. Retourne `200 { id, version }` où `id` est celui de la
/// NOUVELLE ligne.
pub async fn patch_consent_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(id): Path<Uuid>,
    Json(body): Json<PatchConsentTemplateBody>,
) -> Result<Json<ConsentTemplateIdResponse>, AppError> {
    if body.title.as_deref().is_some_and(|s| s.trim().is_empty())
        || body
            .body_markdown
            .as_deref()
            .is_some_and(|s| s.trim().is_empty())
    {
        return Err(AppError::ValidationError);
    }
    if let Some(act_category) = &body.act_category {
        validate_act_category(act_category)?;
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let current = sqlx::query(
        "SELECT act_category, title, body_markdown, version FROM consent_template \
         WHERE id = $1 AND cabinet_id = $2",
    )
    .bind(id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let cur_act_category: String = current
        .try_get("act_category")
        .map_err(|_| AppError::Internal)?;
    let cur_title: String = current.try_get("title").map_err(|_| AppError::Internal)?;
    let cur_body: String = current
        .try_get("body_markdown")
        .map_err(|_| AppError::Internal)?;
    let cur_version: i32 = current.try_get("version").map_err(|_| AppError::Internal)?;

    let new_act_category = body.act_category.unwrap_or(cur_act_category);
    let new_title = body
        .title
        .map(|s| s.trim().to_string())
        .unwrap_or(cur_title);
    let new_body = body
        .body_markdown
        .map(|s| s.trim().to_string())
        .unwrap_or(cur_body);

    text_validation::reject_nul_byte(&new_title)?;
    text_validation::reject_nul_byte(&new_body)?;
    text_validation::validate_max_len(&new_title, MAX_TITLE_LEN)?;
    text_validation::validate_max_len(&new_body, MAX_BODY_LEN)?;

    sqlx::query("UPDATE consent_template SET is_active = false WHERE id = $1 AND cabinet_id = $2")
        .bind(id)
        .bind(claims.cabinet_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let new_version = cur_version + 1;
    let inserted = sqlx::query(
        "INSERT INTO consent_template (cabinet_id, act_category, title, body_markdown, version) \
         VALUES ($1, $2, $3, $4, $5) \
         RETURNING id, version",
    )
    .bind(claims.cabinet_id)
    .bind(&new_act_category)
    .bind(&new_title)
    .bind(&new_body)
    .bind(new_version)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let new_id: Uuid = inserted.try_get("id").map_err(|_| AppError::Internal)?;
    let returned_version: i32 = inserted
        .try_get("version")
        .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        old_template_id = %id,
        new_template_id = %new_id,
        version = returned_version,
        "consent template patched (new version)"
    );

    Ok(Json(ConsentTemplateIdResponse {
        id: new_id,
        version: returned_version,
    }))
}

// ── POST /v1/consent-templates/:id/render ────────────────────────────────────

/// Corps de `POST /v1/consent-templates/:id/render`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RenderConsentTemplateBody {
    pub quote_id: Uuid,
}

/// Réponse de `POST /v1/consent-templates/:id/render`.
#[derive(Serialize)]
pub struct RenderConsentTemplateResponse {
    pub document_id: Uuid,
    pub filename: String,
    pub size_bytes: i64,
    /// Corps rendu (texte brut), pour prévisualisation côté client.
    pub body: String,
}

fn push_unique(list: &mut Vec<String>, value: String) {
    if !list.iter().any(|v| v == &value) {
        list.push(value);
    }
}

/// `POST /v1/consent-templates/:id/render` — rend un modèle pour un patient
/// et un devis, stocké comme document patient (PDF).
///
/// `ProBillingClaims` (même garde que le reste du domaine devis, DP-F5.b) :
/// devis inexistant/hors tenant → `404`. Modèle inexistant ou privé d'un
/// autre cabinet (RLS `tenant_isolation`/`global_template_read`) → `404`
/// (même doctrine que `prescription_templates::apply_prescription_template` :
/// pas de distinction entre les deux cas).
/// Nom/prénom du patient et dent(s)/acte(s) du devis (`quote_item.tooth`/
/// `label`) : substitués dans les placeholders `{{patient.nom}}`,
/// `{{patient.prenom}}`, `{{dents}}`, `{{actes}}` s'ils apparaissent dans
/// `body_markdown`, et toujours résumés dans un bloc d'identification en
/// tête du document (voir doc de module).
/// PDF produit par `pdf_text`, stocké `document.category = 'consentement'`,
/// audit `render_consent_template`. Retourne `201 { document_id, filename,
/// size_bytes, body }` — l'attachement au devis se fait séparément via
/// `POST /v1/cabinet/quotes/:id/attachments` (`kind: "consent"`, #7203).
pub async fn render_consent_template(
    State(state): State<AppState>,
    claims: ProBillingClaims,
    Extension(object_storage): Extension<std::sync::Arc<dyn ObjectStorage>>,
    Path(id): Path<Uuid>,
    Json(body): Json<RenderConsentTemplateBody>,
) -> Result<(StatusCode, Json<RenderConsentTemplateResponse>), AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let quote_row = sqlx::query(
        "SELECT patient_id FROM quote \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(body.quote_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let patient_id: Uuid = quote_row
        .try_get("patient_id")
        .map_err(|_| AppError::Internal)?;

    // RLS (tenant_isolation OR global_template_read) rend invisible tout
    // modèle privé d'un autre cabinet : même 404 que « n'existe pas ».
    let tmpl_row = sqlx::query(
        "SELECT act_category, title, body_markdown FROM consent_template WHERE id = $1",
    )
    .bind(id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let act_category: String = tmpl_row
        .try_get("act_category")
        .map_err(|_| AppError::Internal)?;
    let title: String = tmpl_row.try_get("title").map_err(|_| AppError::Internal)?;
    let body_markdown: String = tmpl_row
        .try_get("body_markdown")
        .map_err(|_| AppError::Internal)?;

    let patient_row = sqlx::query(
        "SELECT first_name, last_name, birth_date FROM patient \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;
    let first_name: String = patient_row
        .try_get("first_name")
        .map_err(|_| AppError::Internal)?;
    let last_name: String = patient_row
        .try_get("last_name")
        .map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> = patient_row
        .try_get("birth_date")
        .map_err(|_| AppError::Internal)?;

    let item_rows =
        sqlx::query("SELECT label, tooth FROM quote_item WHERE quote_id = $1 ORDER BY id")
            .bind(body.quote_id)
            .fetch_all(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;

    let mut acts: Vec<String> = Vec::new();
    let mut teeth: Vec<String> = Vec::new();
    for row in &item_rows {
        let label: String = row.try_get("label").map_err(|_| AppError::Internal)?;
        push_unique(&mut acts, label);
        let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
        if let Some(tooth) = tooth {
            push_unique(&mut teeth, tooth);
        }
    }
    let acts_summary = if acts.is_empty() {
        "non renseigné(s)".to_string()
    } else {
        acts.join(", ")
    };
    let teeth_summary = if teeth.is_empty() {
        "non renseignée(s)".to_string()
    } else {
        teeth.join(", ")
    };

    let cab_row = sqlx::query("SELECT raison_sociale FROM cabinet WHERE id = $1")
        .bind(claims.cabinet_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::Internal)?;
    let cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;

    let substituted_body = body_markdown
        .replace("{{patient.prenom}}", &first_name)
        .replace("{{patient.nom}}", &last_name)
        .replace("{{dents}}", &teeth_summary)
        .replace("{{actes}}", &acts_summary);

    let birth_suffix = birth_date
        .map(|d| format!(" (né(e) le {})", d.format("%d/%m/%Y")))
        .unwrap_or_default();
    let rendered = format!(
        "Patient : {first_name} {last_name}{birth_suffix}\n\
         Acte(s) concerné(s) : {acts_summary}\n\
         Dent(s) concernée(s) : {teeth_summary}\n\n\
         {substituted_body}"
    );

    let header = vec![cabinet_name, title.clone()];
    let body_lines = pdf_text::wrap_lines(&rendered, pdf_text::WRAP_COLUMNS);
    let pdf_bytes = pdf_text::build_text_pdf(&header, &body_lines, &[]);
    let size_bytes = pdf_bytes.len() as i64;
    let document_id = Uuid::new_v4();
    let storage_key = format!("consentements/{}/{}.pdf", claims.cabinet_id, document_id);
    let filename = format!("consentement-{act_category}-{document_id}.pdf");

    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes.clone())
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'consentement', $4, $5, 'application/pdf', \
                 encode(digest($6, 'sha256'), 'hex'), 'clean', $7, $8)",
    )
    .bind(document_id)
    .bind(claims.cabinet_id)
    .bind(patient_id)
    .bind(&storage_key)
    .bind(&filename)
    .bind(&pdf_bytes)
    .bind(claims.sub)
    .bind(size_bytes)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO audit_log \
         (cabinet_id, actor_id, actor_role, action, entity, entity_id) \
         VALUES ($1, $2, $3, 'render_consent_template', 'document', $4)",
    )
    .bind(claims.cabinet_id)
    .bind(claims.sub)
    .bind(&claims.role)
    .bind(document_id)
    .execute(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        patient_id = %patient_id,
        quote_id = %body.quote_id,
        template_id = %id,
        document_id = %document_id,
        size_bytes,
        "consent template rendered"
    );

    Ok((
        StatusCode::CREATED,
        Json(RenderConsentTemplateResponse {
            document_id,
            filename,
            size_bytes,
            body: rendered,
        }),
    ))
}
