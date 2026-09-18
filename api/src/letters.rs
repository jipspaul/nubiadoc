//! Moteur de courriers types (#7197, parité Dental Pilot F7.a) :
//! `GET`/`POST /v1/letter-templates` et `POST /v1/patients/:id/letters`.
//!
//! S'appuie sur `letter_template` (migrations 0167 + 0267) : lecture scopée
//! cabinet + modèles globaux seedés via RLS (`tenant_isolation` +
//! `global_template_read`), même modèle que `prescription_templates.rs`.
//!
//! Le moteur de substitution ([`render`]) est pur et testé unitairement :
//! un placeholder `{{ns.champ}}` hors de [`KNOWN_PLACEHOLDERS`] est refusé
//! (`422 unknown_placeholders` avec la liste), une valeur absente du
//! contexte (pas de RDV, pas de RPPS, pas de correspondant…) et non fournie
//! par `overrides` est refusée (`422 missing_placeholder_values` avec la
//! liste) — jamais de courrier rendu avec un trou. Substitution en une
//! passe : une valeur contenant `{{…}}` n'est pas ré-interprétée.
//!
//! Le PDF (en-tête/pied cabinet + RPPS, pagination) est produit par
//! `pdf_text::build_text_pdf` (même mécanique sans crate que les devis et
//! ordonnances) et stocké comme document patient (`document.category =
//! 'courrier'`, Object Storage) — pas de stockage dédié.

use std::collections::BTreeMap;

use axum::{
    extract::{Extension, Path, State},
    http::StatusCode,
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProSecretaryPlusClaims},
    patient_tags::ensure_secretary_scope,
    pdf_text, AppState,
};

/// Placeholders reconnus par le moteur (forme `{{nom}}`, espaces internes
/// tolérés : `{{ patient.nom }}`). Documentés dans `docs/12-api-reference.md`.
pub(crate) const KNOWN_PLACEHOLDERS: &[&str] = &[
    "patient.prenom",
    "patient.nom",
    "patient.date_naissance",
    "cabinet.nom",
    "cabinet.adresse",
    "cabinet.telephone",
    "praticien.nom",
    "praticien.rpps",
    "rdv.date",
    "rdv.heure",
    "date.aujourdhui",
    "correspondant.nom",
];

/// Valeurs de `letter_template.kind` (CHECK, migrations 0167 + 0267).
const VALID_KINDS: &[&str] = &[
    "convocation",
    "relance",
    "courrier_confrere",
    "attestation",
    "autre",
];

/// Taille maximale d'un corps de modèle (garde-fou mémoire/PDF).
const MAX_BODY_CHARS: usize = 20_000;

/// Taille maximale du nom d'un modèle (#7253 : aucune borne auparavant, un
/// `name` de plusieurs milliers de caractères était accepté alors que
/// `body_template` l'est déjà via `MAX_BODY_CHARS`).
const MAX_NAME_CHARS: usize = 200;

/// Taille maximale d'une valeur d'`overrides` (#7253 : aucune borne
/// auparavant — la valeur part telle quelle dans le corps rendu puis le
/// PDF, seule la clé était contrôlée via `KNOWN_PLACEHOLDERS`).
const MAX_OVERRIDE_VALUE_CHARS: usize = 500;

// ── Moteur de substitution (pur) ─────────────────────────────────────────────

/// Erreur du moteur, convertie en `AppError` par les handlers.
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum RenderError {
    /// `{{` sans `}}` fermant.
    Malformed,
    /// Placeholders hors [`KNOWN_PLACEHOLDERS`] (dédoublonnés, ordre d'apparition).
    Unknown(Vec<String>),
    /// Placeholders connus mais sans valeur dans le contexte (idem).
    Missing(Vec<String>),
}

impl From<RenderError> for AppError {
    fn from(err: RenderError) -> Self {
        match err {
            RenderError::Malformed => AppError::ValidationError,
            RenderError::Unknown(list) => AppError::UnknownPlaceholders(list),
            RenderError::Missing(list) => AppError::MissingPlaceholderValues(list),
        }
    }
}

/// Un segment du modèle une fois analysé.
#[derive(Debug, PartialEq, Eq)]
enum Segment<'a> {
    Text(&'a str),
    Placeholder(String),
}

/// Découpe `template` en segments texte / placeholder. Un `{{` non fermé →
/// [`RenderError::Malformed`]. Le nom du placeholder est `trim()`é.
fn parse(template: &str) -> Result<Vec<Segment<'_>>, RenderError> {
    let mut segments = Vec::new();
    let mut rest = template;
    while let Some(start) = rest.find("{{") {
        if start > 0 {
            segments.push(Segment::Text(&rest[..start]));
        }
        let after = &rest[start + 2..];
        let Some(end) = after.find("}}") else {
            return Err(RenderError::Malformed);
        };
        segments.push(Segment::Placeholder(after[..end].trim().to_string()));
        rest = &after[end + 2..];
    }
    if !rest.is_empty() {
        segments.push(Segment::Text(rest));
    }
    Ok(segments)
}

fn push_unique(list: &mut Vec<String>, name: &str) {
    if !list.iter().any(|n| n == name) {
        list.push(name.to_string());
    }
}

/// Placeholders utilisés par `template`, dédoublonnés, dans l'ordre
/// d'apparition. Erreur si le modèle est mal formé ou référence un
/// placeholder inconnu.
pub(crate) fn placeholders(template: &str) -> Result<Vec<String>, RenderError> {
    let mut used = Vec::new();
    let mut unknown = Vec::new();
    for segment in parse(template)? {
        if let Segment::Placeholder(name) = segment {
            if KNOWN_PLACEHOLDERS.contains(&name.as_str()) {
                push_unique(&mut used, &name);
            } else {
                push_unique(&mut unknown, &name);
            }
        }
    }
    if !unknown.is_empty() {
        return Err(RenderError::Unknown(unknown));
    }
    Ok(used)
}

/// Substitue les placeholders de `template` par `values`. Une clé de
/// `values` hors [`KNOWN_PLACEHOLDERS`] est ignorée (les handlers les
/// valident en amont). Les valeurs sont insérées telles quelles (texte
/// brut) : l'échappement est fait par la couche de sortie (PDF), jamais ici,
/// et une valeur contenant `{{…}}` n'est pas ré-interprétée.
pub(crate) fn render(
    template: &str,
    values: &BTreeMap<String, String>,
) -> Result<String, RenderError> {
    let segments = parse(template)?;
    let mut unknown = Vec::new();
    let mut missing = Vec::new();
    let mut out = String::with_capacity(template.len());
    for segment in &segments {
        match segment {
            Segment::Text(text) => out.push_str(text),
            Segment::Placeholder(name) => {
                if !KNOWN_PLACEHOLDERS.contains(&name.as_str()) {
                    push_unique(&mut unknown, name);
                } else if let Some(value) = values.get(name) {
                    out.push_str(value);
                } else {
                    push_unique(&mut missing, name);
                }
            }
        }
    }
    if !unknown.is_empty() {
        return Err(RenderError::Unknown(unknown));
    }
    if !missing.is_empty() {
        return Err(RenderError::Missing(missing));
    }
    Ok(out)
}

// ── GET /v1/letter-templates ─────────────────────────────────────────────────

/// Un courrier type, vu du cabinet courant.
#[derive(Serialize)]
pub struct LetterTemplateDto {
    pub id: Uuid,
    pub name: String,
    pub kind: String,
    pub body_template: String,
    /// `true` : modèle global seedé (`cabinet_id IS NULL`), lecture seule.
    pub is_global: bool,
    /// Placeholders utilisés par le modèle (aide à la saisie des `overrides`).
    pub placeholders: Vec<String>,
    pub created_at: String,
}

/// `GET /v1/letter-templates` — liste les courriers types visibles.
///
/// Token pro `secretary`/`practitioner`/`admin` requis. RLS scopée via
/// `app.current_cabinet_id` : modèles propres au cabinet ET modèles
/// globaux (`cabinet_id IS NULL`). Tri : globaux d'abord, puis par nom.
pub async fn list_letter_templates(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
) -> Result<Json<Vec<LetterTemplateDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, name, kind, body_template, (cabinet_id IS NULL) AS is_global, created_at \
         FROM letter_template \
         ORDER BY (cabinet_id IS NULL) DESC, name",
    )
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut templates = Vec::with_capacity(rows.len());
    for row in &rows {
        let body_template: String = row
            .try_get("body_template")
            .map_err(|_| AppError::Internal)?;
        // Un modèle inséré hors API (seed, SQL direct) peut référencer un
        // placeholder inconnu : on le liste quand même, avec la liste vide —
        // le rendu, lui, le refusera en 422.
        let placeholders = placeholders(&body_template).unwrap_or_default();
        let created_at: chrono::DateTime<chrono::Utc> =
            row.try_get("created_at").map_err(|_| AppError::Internal)?;
        templates.push(LetterTemplateDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            name: row.try_get("name").map_err(|_| AppError::Internal)?,
            kind: row.try_get("kind").map_err(|_| AppError::Internal)?,
            body_template,
            is_global: row.try_get("is_global").map_err(|_| AppError::Internal)?,
            placeholders,
            created_at: created_at.to_rfc3339(),
        });
    }

    Ok(Json(templates))
}

// ── POST /v1/letter-templates ────────────────────────────────────────────────

/// Body de `POST /v1/letter-templates`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CreateLetterTemplateBody {
    pub name: String,
    /// `convocation` | `relance` | `courrier_confrere` | `attestation` | `autre`.
    pub kind: String,
    pub body_template: String,
}

/// Réponse de `POST /v1/letter-templates`.
#[derive(Serialize)]
pub struct CreateLetterTemplateResponse {
    pub template_id: Uuid,
    pub placeholders: Vec<String>,
}

/// `POST /v1/letter-templates` — crée un courrier type propre au cabinet.
///
/// - Token pro `secretary`/`practitioner`/`admin` requis.
/// - `cabinet_id` extrait du JWT — jamais `NULL` (seule une migration crée
///   un modèle global, cf. RLS `global_template_read`).
/// - `name`/`body_template` non blancs, `kind` dans l'énum, `name` ≤
///   `MAX_NAME_CHARS`, `body_template` ≤ `MAX_BODY_CHARS` → `422
///   validation_error` sinon.
/// - `body_template` mal formé (`{{` non fermé) → `422 validation_error` ;
///   placeholder inconnu → `422 unknown_placeholders { placeholders: [...] }`.
/// - Retourne `201 { template_id, placeholders }`.
pub async fn create_letter_template(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Json(body): Json<CreateLetterTemplateBody>,
) -> Result<(StatusCode, Json<CreateLetterTemplateResponse>), AppError> {
    let name = body.name.trim();
    if name.is_empty() || body.body_template.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.body_template.chars().count() > MAX_BODY_CHARS {
        return Err(AppError::ValidationError);
    }
    if name.chars().count() > MAX_NAME_CHARS {
        return Err(AppError::ValidationError);
    }
    if !VALID_KINDS.contains(&body.kind.as_str()) {
        return Err(AppError::ValidationError);
    }
    crate::text_validation::reject_nul_byte(name)?;
    crate::text_validation::reject_nul_byte(&body.body_template)?;
    let placeholders = placeholders(&body.body_template)?;

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let row = sqlx::query(
        "INSERT INTO letter_template (cabinet_id, name, kind, body_template) \
         VALUES ($1, $2, $3, $4) RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(name)
    .bind(&body.kind)
    .bind(&body.body_template)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let template_id: Uuid = row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %template_id,
        kind = %body.kind,
        "letter template created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreateLetterTemplateResponse {
            template_id,
            placeholders,
        }),
    ))
}

// ── POST /v1/patients/:id/letters ────────────────────────────────────────────

/// Body de `POST /v1/patients/:id/letters`.
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct GenerateLetterBody {
    pub template_id: Uuid,
    /// Réservé : aucune entité « correspondant cabinet » n'existe encore
    /// (`patient_correspondent`, migration 0176, est scopée compte patient,
    /// invisible d'une session cabinet). Toute valeur → `501
    /// correspondent_not_supported` ; passer `{{correspondant.nom}}` via
    /// `overrides` en attendant.
    pub correspondent_id: Option<Uuid>,
    /// Valeurs forcées, clé = placeholder sans accolades (ex. `"rdv.date"`).
    /// Priment sur les valeurs résolues en base. Clé inconnue → `422
    /// unknown_placeholders`.
    #[serde(default)]
    pub overrides: BTreeMap<String, String>,
}

/// Réponse de `POST /v1/patients/:id/letters`.
#[derive(Serialize)]
pub struct GenerateLetterResponse {
    pub document_id: Uuid,
    pub filename: String,
    pub size_bytes: i64,
    /// Corps rendu (texte brut), pour prévisualisation côté client.
    pub body: String,
}

/// Contexte résolu en base pour un patient (valeurs `None` = non
/// disponibles ; deviennent `missing` au rendu sauf override).
struct LetterContext {
    values: BTreeMap<String, String>,
    header: Vec<String>,
    footer: Vec<String>,
    kind: String,
}

fn insert_opt(values: &mut BTreeMap<String, String>, key: &str, value: Option<String>) {
    if let Some(v) = value {
        let v = v.trim().to_string();
        if !v.is_empty() {
            values.insert(key.to_string(), v);
        }
    }
}

/// `POST /v1/patients/:id/letters` — rend un courrier type pour un patient
/// et le stocke comme document patient (PDF).
///
/// - Token pro `secretary`/`practitioner`/`admin` requis. Patient hors
///   cabinet (ou hors scope secrétariat, R10) → `404`.
/// - `template_id` inexistant ou privé d'un autre cabinet → `404` (RLS).
/// - `correspondent_id` fourni → `501 correspondent_not_supported`.
/// - Clé d'`overrides` inconnue, ou placeholder inconnu dans le modèle →
///   `422 unknown_placeholders { placeholders }`. Valeur d'`overrides` >
///   `MAX_OVERRIDE_VALUE_CHARS` → `422 validation_error`.
/// - Placeholder sans valeur (pas de RDV, pas de RPPS, correspondant…) et
///   sans override → `422 missing_placeholder_values { placeholders }`.
/// - Contexte : `rdv.*` = prochain RDV non annulé du patient dans le cabinet,
///   sinon le dernier passé ; `praticien.*` = le praticien appelant si
///   `role = practitioner`, sinon celui du RDV retenu ; `cabinet.*` depuis
///   `cabinet.raison_sociale` / `settings.address` / `settings.contact.phone`,
///   `cabinet.adresse` retombant sur l'annuaire (`establishment`, #3557/#7242)
///   quand `settings` n'a pas d'adresse.
/// - PDF : en-tête (cabinet, adresse, téléphone, praticien + RPPS, date),
///   corps replié, pied (cabinet + RPPS, numéro de page). Uploadé dans
///   l'Object Storage, `document.category = 'courrier'`, audit
///   `generate_letter`. Retourne `201 { document_id, filename, size_bytes, body }`.
pub async fn generate_patient_letter(
    State(state): State<AppState>,
    claims: ProSecretaryPlusClaims,
    Extension(object_storage): Extension<std::sync::Arc<dyn crate::ObjectStorage>>,
    Path(patient_id): Path<Uuid>,
    Json(body): Json<GenerateLetterBody>,
) -> Result<(StatusCode, Json<GenerateLetterResponse>), AppError> {
    if body.correspondent_id.is_some() {
        return Err(AppError::CorrespondentNotSupported);
    }
    let unknown_overrides: Vec<String> = body
        .overrides
        .keys()
        .filter(|k| !KNOWN_PLACEHOLDERS.contains(&k.as_str()))
        .cloned()
        .collect();
    if !unknown_overrides.is_empty() {
        return Err(AppError::UnknownPlaceholders(unknown_overrides));
    }
    for value in body.overrides.values() {
        crate::text_validation::reject_nul_byte(value)?;
        if value.chars().count() > MAX_OVERRIDE_VALUE_CHARS {
            return Err(AppError::ValidationError);
        }
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
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
    ensure_secretary_scope(&mut tx, &claims, patient_id).await?;

    // RLS (tenant_isolation OR global_template_read) : un modèle privé d'un
    // autre cabinet est invisible → même 404 que « n'existe pas ».
    let tmpl_row = sqlx::query("SELECT kind, body_template FROM letter_template WHERE id = $1")
        .bind(body.template_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;
    let kind: String = tmpl_row.try_get("kind").map_err(|_| AppError::Internal)?;
    let body_template: String = tmpl_row
        .try_get("body_template")
        .map_err(|_| AppError::Internal)?;
    // Placeholder inconnu dans un modèle inséré hors API → 422 explicite
    // avant toute lecture supplémentaire.
    placeholders(&body_template)?;

    let ctx = resolve_context(&mut tx, &claims, patient_id, &patient_row, kind).await?;
    let mut values = ctx.values;
    for (key, value) in &body.overrides {
        values.insert(key.clone(), value.trim().to_string());
    }
    let rendered = render(&body_template, &values)?;

    let body_lines = pdf_text::wrap_lines(&rendered, pdf_text::WRAP_COLUMNS);
    let pdf_bytes = pdf_text::build_text_pdf(&ctx.header, &body_lines, &ctx.footer);
    let size_bytes = pdf_bytes.len() as i64;
    let document_id = Uuid::new_v4();
    let storage_key = format!("courriers/{}/{}.pdf", claims.cabinet_id, document_id);
    let filename = format!("courrier-{}-{}.pdf", ctx.kind, document_id);

    // Même pattern que `billing::generate_quote_document` : la clé doit
    // référencer un objet effectivement écrit.
    object_storage
        .upload(&storage_key, "application/pdf", pdf_bytes.clone())
        .await
        .map_err(|_| AppError::Internal)?;

    sqlx::query(
        "INSERT INTO document \
         (id, cabinet_id, patient_id, category, storage_key, filename, mime_type, \
          sha256, scan_status, uploaded_by, size_bytes) \
         VALUES ($1, $2, $3, 'courrier', $4, $5, 'application/pdf', \
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
         VALUES ($1, $2, $3, 'generate_letter', 'document', $4)",
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
        template_id = %body.template_id,
        document_id = %document_id,
        size_bytes,
        "patient letter generated"
    );

    Ok((
        StatusCode::CREATED,
        Json(GenerateLetterResponse {
            document_id,
            filename,
            size_bytes,
            body: rendered,
        }),
    ))
}

/// Résout patient / cabinet / praticien / RDV / date du jour en base et
/// prépare l'en-tête et le pied du PDF.
async fn resolve_context(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    claims: &ProSecretaryPlusClaims,
    patient_id: Uuid,
    patient_row: &sqlx::postgres::PgRow,
    kind: String,
) -> Result<LetterContext, AppError> {
    let mut values = BTreeMap::new();

    let first_name: String = patient_row
        .try_get("first_name")
        .map_err(|_| AppError::Internal)?;
    let last_name: String = patient_row
        .try_get("last_name")
        .map_err(|_| AppError::Internal)?;
    let birth_date: Option<chrono::NaiveDate> = patient_row
        .try_get("birth_date")
        .map_err(|_| AppError::Internal)?;
    insert_opt(&mut values, "patient.prenom", Some(first_name));
    insert_opt(&mut values, "patient.nom", Some(last_name));
    insert_opt(
        &mut values,
        "patient.date_naissance",
        birth_date.map(|d| d.format("%d/%m/%Y").to_string()),
    );

    let cab_row = sqlx::query(
        "SELECT raison_sociale, \
                settings->>'address' AS address, \
                COALESCE(settings->'contact'->>'phone', settings->>'phone', \
                         settings->>'telephone') AS phone \
         FROM cabinet WHERE id = $1",
    )
    .bind(claims.cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::Internal)?;
    let cabinet_name: String = cab_row
        .try_get("raison_sociale")
        .map_err(|_| AppError::Internal)?;
    let cabinet_address: Option<String> =
        cab_row.try_get("address").map_err(|_| AppError::Internal)?;
    let cabinet_phone: Option<String> = cab_row.try_get("phone").map_err(|_| AppError::Internal)?;

    // Fallback annuaire quand `cabinet.settings` n'a pas d'adresse (#3557) :
    // même mécanisme que `appointments_response::fetch_cabinet_for_response`.
    let cabinet_address = if cabinet_address.is_some() {
        cabinet_address
    } else {
        let est_row = sqlx::query(
            "SELECT e.address AS establishment_address \
             FROM provider p \
             JOIN establishment e ON e.id = p.establishment_id \
             WHERE p.cabinet_id = $1 \
             ORDER BY p.is_listed DESC, p.created_at ASC \
             LIMIT 1",
        )
        .bind(claims.cabinet_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?;

        est_row
            .and_then(|r| {
                r.try_get::<serde_json::Value, _>("establishment_address")
                    .ok()
            })
            .as_ref()
            .and_then(crate::appointments_response::format_establishment_address)
    };
    insert_opt(&mut values, "cabinet.nom", Some(cabinet_name.clone()));
    insert_opt(&mut values, "cabinet.adresse", cabinet_address.clone());
    insert_opt(&mut values, "cabinet.telephone", cabinet_phone.clone());

    // RDV : prochain non annulé, sinon le dernier passé.
    let rdv_row = sqlx::query(
        "SELECT starts_at, practitioner_id FROM appointment \
         WHERE patient_id = $1 AND cabinet_id = $2 \
           AND deleted_at IS NULL AND status <> 'cancelled' \
         ORDER BY (starts_at >= now()) DESC, \
                  CASE WHEN starts_at >= now() THEN starts_at END ASC, \
                  starts_at DESC \
         LIMIT 1",
    )
    .bind(patient_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut **tx)
    .await
    .map_err(|_| AppError::Internal)?;
    let mut rdv_practitioner_id: Option<Uuid> = None;
    if let Some(row) = &rdv_row {
        let starts_at: chrono::DateTime<chrono::Utc> =
            row.try_get("starts_at").map_err(|_| AppError::Internal)?;
        rdv_practitioner_id = row
            .try_get("practitioner_id")
            .map_err(|_| AppError::Internal)?;
        insert_opt(
            &mut values,
            "rdv.date",
            Some(crate::scheduling::format_paris_date(starts_at)),
        );
        insert_opt(
            &mut values,
            "rdv.heure",
            Some(crate::scheduling::format_paris_time(starts_at)),
        );
    }

    // Praticien : l'appelant s'il est praticien, sinon celui du RDV retenu.
    let prac_row = if claims.role == "practitioner" {
        sqlx::query(
            "SELECT rpps, practitioner_display_name(id) AS display_name \
             FROM practitioner WHERE cabinet_id = $1 AND user_id = $2",
        )
        .bind(claims.cabinet_id)
        .bind(claims.sub)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else if let Some(prac_id) = rdv_practitioner_id {
        sqlx::query(
            "SELECT rpps, practitioner_display_name(id) AS display_name \
             FROM practitioner WHERE cabinet_id = $1 AND id = $2",
        )
        .bind(claims.cabinet_id)
        .bind(prac_id)
        .fetch_optional(&mut **tx)
        .await
        .map_err(|_| AppError::Internal)?
    } else {
        None
    };
    let mut prac_name: Option<String> = None;
    let mut prac_rpps: Option<String> = None;
    if let Some(row) = &prac_row {
        prac_name = row
            .try_get("display_name")
            .map_err(|_| AppError::Internal)?;
        prac_rpps = row.try_get("rpps").map_err(|_| AppError::Internal)?;
    }
    insert_opt(&mut values, "praticien.nom", prac_name.clone());
    insert_opt(&mut values, "praticien.rpps", prac_rpps.clone());

    let today = crate::scheduling::format_paris_date(chrono::Utc::now());
    insert_opt(&mut values, "date.aujourdhui", Some(today.clone()));

    // En-tête / pied standardisés (texte : pas de logo dans un PDF sans
    // crate — cf. note de module). Chaque ligne absente est simplement omise.
    let mut header = vec![cabinet_name.clone()];
    if let Some(addr) = &cabinet_address {
        header.push(addr.clone());
    }
    if let Some(phone) = &cabinet_phone {
        header.push(format!("Tél. {phone}"));
    }
    if let Some(name) = &prac_name {
        header.push(match &prac_rpps {
            Some(rpps) => format!("{name} — RPPS {rpps}"),
            None => name.clone(),
        });
    }
    header.push(format!("Le {today}"));

    let mut footer_parts = vec![cabinet_name];
    if let Some(addr) = &cabinet_address {
        footer_parts.push(addr.clone());
    }
    if let Some(phone) = &cabinet_phone {
        footer_parts.push(format!("Tél. {phone}"));
    }
    if let Some(rpps) = &prac_rpps {
        footer_parts.push(format!("RPPS {rpps}"));
    }
    let footer = vec![footer_parts.join(" — ")];

    Ok(LetterContext {
        values,
        header,
        footer,
        kind,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ctx(pairs: &[(&str, &str)]) -> BTreeMap<String, String> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn render_substitutes_known_placeholders() {
        let out = render(
            "Bonjour {{patient.prenom}} {{ patient.nom }}, RDV le {{rdv.date}}.",
            &ctx(&[
                ("patient.prenom", "Léa"),
                ("patient.nom", "Dupont"),
                ("rdv.date", "12/10/2026"),
            ]),
        )
        .unwrap();
        assert_eq!(out, "Bonjour Léa Dupont, RDV le 12/10/2026.");
    }

    #[test]
    fn render_rejects_unknown_placeholders_with_list() {
        let err = render(
            "{{patient.prenom}} {{devis.date}} {{foo}} {{devis.date}}",
            &ctx(&[("patient.prenom", "Léa")]),
        )
        .unwrap_err();
        assert_eq!(
            err,
            RenderError::Unknown(vec!["devis.date".to_string(), "foo".to_string()])
        );
    }

    #[test]
    fn render_rejects_missing_values_with_list() {
        let err = render(
            "{{patient.prenom}} le {{rdv.date}} à {{rdv.heure}} ({{rdv.date}})",
            &ctx(&[("patient.prenom", "Léa")]),
        )
        .unwrap_err();
        assert_eq!(
            err,
            RenderError::Missing(vec!["rdv.date".to_string(), "rdv.heure".to_string()])
        );
    }

    #[test]
    fn render_rejects_unclosed_placeholder() {
        assert_eq!(
            render("Bonjour {{patient.prenom", &ctx(&[])).unwrap_err(),
            RenderError::Malformed
        );
        assert_eq!(placeholders("{{").unwrap_err(), RenderError::Malformed);
    }

    #[test]
    fn render_is_single_pass_and_keeps_values_verbatim() {
        // Une valeur contenant un placeholder ou des délimiteurs PDF n'est
        // ni ré-interprétée ni altérée par le moteur (échappement en sortie).
        let out = render(
            "X {{patient.nom}} Y",
            &ctx(&[("patient.nom", "{{cabinet.nom}} (a) \\ b")]),
        )
        .unwrap();
        assert_eq!(out, "X {{cabinet.nom}} (a) \\ b Y");
        let escaped = pdf_text::escape_winansi(&out);
        assert_eq!(escaped, b"X {{cabinet.nom}} \\(a\\) \\\\ b Y".to_vec());
    }

    #[test]
    fn render_without_placeholders_is_identity() {
        assert_eq!(render("Texte brut.", &ctx(&[])).unwrap(), "Texte brut.");
        assert_eq!(placeholders("Texte brut.").unwrap(), Vec::<String>::new());
    }

    #[test]
    fn placeholders_are_unique_in_order_of_appearance() {
        let list =
            placeholders("{{rdv.date}} {{patient.nom}} {{rdv.date}} {{ cabinet.nom }}").unwrap();
        assert_eq!(list, vec!["rdv.date", "patient.nom", "cabinet.nom"]);
    }

    #[test]
    fn every_known_placeholder_renders() {
        let template: String = KNOWN_PLACEHOLDERS
            .iter()
            .map(|p| format!("{{{{{p}}}}}"))
            .collect::<Vec<_>>()
            .join("|");
        let values: BTreeMap<String, String> = KNOWN_PLACEHOLDERS
            .iter()
            .map(|p| (p.to_string(), format!("<{p}>")))
            .collect();
        let out = render(&template, &values).unwrap();
        for p in KNOWN_PLACEHOLDERS {
            assert!(out.contains(&format!("<{p}>")));
        }
        assert!(!out.contains("{{"));
    }
}
