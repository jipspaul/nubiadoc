//! Handlers `prescription_template` (#4074) : `GET`/`POST
//! /v1/cabinet/prescription-templates` et `POST
//! /v1/cabinet/prescriptions/:id/apply-template`.
//!
//! Extrait dans un module dédié plutôt que `prescriptions.rs` (déjà à 768
//! lignes, CLAUDE.md plafond absolu 700 — refactor de ce fichier hors
//! scope ici, cf. jugement déjà appliqué à `auth/mod.rs`/`lib.rs` cette
//! session : petit ajout, gros refactor différé).
//!
//! S'appuie sur `prescription_template` (migration 0166, #4073) : lecture
//! scopée cabinet + modèles globaux via RLS (`tenant_isolation` +
//! `global_template_read`) — un modèle privé d'un AUTRE cabinet est
//! invisible par construction, pas de vérification applicative
//! supplémentaire nécessaire pour `apply-template` (404 naturel).

use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::Json;
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Ligne d'un modèle : même forme que `prescription_item`
/// (`prescriptions::PrescriptionItemInput`), dupliquée ici en local pour
/// éviter de dépendre de `prescriptions.rs` (fichier déjà au plafond).
#[derive(Deserialize, Serialize, Clone)]
pub struct TemplateItemInput {
    pub label: String,
    pub form: Option<String>,
    pub posology: String,
    pub duration: String,
    pub quantity: Option<String>,
}

// ── GET /v1/cabinet/prescription-templates ──────────────────────────────────

/// Un modèle d'ordonnance, vu du cabinet courant.
#[derive(Serialize)]
pub struct PrescriptionTemplateDto {
    pub id: Uuid,
    pub label: String,
    pub items: serde_json::Value,
    pub is_global: bool,
    /// `true` si modèle personnel (`practitioner_id` non NULL). Permet au
    /// client de distinguer un modèle privé d'un modèle partagé — cf. le
    /// contrat documenté sur `personal` dans `CreatePrescriptionTemplateBody`.
    pub personal: bool,
}

/// `GET /v1/cabinet/prescription-templates` — liste les modèles visibles.
///
/// Auth JWT pro `practitioner`/`admin` requis. RLS scopée via
/// `app.current_cabinet_id` : renvoie les modèles propres au cabinet ET les
/// modèles globaux (`cabinet_id IS NULL`, policy `global_template_read`) —
/// les deux policies RLS s'additionnent (OR). Filtre applicatif en plus :
/// les modèles personnels (`practitioner_id` non NULL) d'un AUTRE praticien
/// sont exclus — seuls les modèles partagés et les modèles personnels du
/// praticien courant sont renvoyés, cf. contrat `personal` du POST.
pub async fn list_prescription_templates(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
) -> Result<Json<Vec<PrescriptionTemplateDto>>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let practitioner_row =
        sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 AND user_id = $2")
            .bind(claims.cabinet_id)
            .bind(claims.sub)
            .fetch_optional(&mut *tx)
            .await
            .map_err(|_| AppError::Internal)?;
    let practitioner_id: Option<Uuid> = practitioner_row
        .map(|row| row.try_get("id"))
        .transpose()
        .map_err(|_| AppError::Internal)?;

    let rows = sqlx::query(
        "SELECT id, label, items, (cabinet_id IS NULL) AS is_global, \
         (practitioner_id IS NOT NULL) AS personal \
         FROM prescription_template \
         WHERE practitioner_id IS NULL OR practitioner_id = $1 \
         ORDER BY is_global, label",
    )
    .bind(practitioner_id)
    .fetch_all(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    let mut templates = Vec::with_capacity(rows.len());
    for row in &rows {
        templates.push(PrescriptionTemplateDto {
            id: row.try_get("id").map_err(|_| AppError::Internal)?,
            label: row.try_get("label").map_err(|_| AppError::Internal)?,
            items: row.try_get("items").map_err(|_| AppError::Internal)?,
            is_global: row.try_get("is_global").map_err(|_| AppError::Internal)?,
            personal: row.try_get("personal").map_err(|_| AppError::Internal)?,
        });
    }

    Ok(Json(templates))
}

// ── POST /v1/cabinet/prescription-templates ──────────────────────────────────

/// Body de `POST /v1/cabinet/prescription-templates`.
#[derive(Deserialize)]
pub struct CreatePrescriptionTemplateBody {
    pub label: String,
    pub items: Vec<TemplateItemInput>,
    /// `true` : modèle personnel (visible seulement du praticien qui l'a
    /// créé — filtré côté client, pas par une policy RLS dédiée : la
    /// distinction personnel/partagé n'a pas de portée sécurité, seulement
    /// organisationnelle, contrairement à cabinet_id qui est un vrai tenant).
    /// `false`/absent : modèle partagé par tout le cabinet.
    pub personal: Option<bool>,
}

/// Réponse de `POST /v1/cabinet/prescription-templates`.
#[derive(Serialize)]
pub struct CreatePrescriptionTemplateResponse {
    pub template_id: Uuid,
}

/// `POST /v1/cabinet/prescription-templates` — crée un modèle propre au cabinet.
///
/// - Auth JWT pro `practitioner`/`admin` requis.
/// - `cabinet_id` extrait du JWT — jamais `NULL` (seule une migration crée
///   un modèle global, cf. RLS `global_template_read`, pas de policy
///   INSERT pour `cabinet_id IS NULL`).
/// - `label` non vide/blanc, `items` non vide et chaque ligne avec
///   `label`/`posology`/`duration` non blancs → 422 sinon (mêmes règles que
///   `create_prescription`, `prescriptions.rs`).
/// - `personal:true` pose `practitioner_id` (résolu depuis le JWT).
/// - Retourne `201 { template_id }`.
pub async fn create_prescription_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Json(body): Json<CreatePrescriptionTemplateBody>,
) -> Result<(StatusCode, Json<CreatePrescriptionTemplateResponse>), AppError> {
    if body.label.trim().is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.items.is_empty() {
        return Err(AppError::ValidationError);
    }
    if body.items.iter().any(|i| {
        i.label.trim().is_empty() || i.posology.trim().is_empty() || i.duration.trim().is_empty()
    }) {
        return Err(AppError::ValidationError);
    }

    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let practitioner_id: Option<Uuid> = if body.personal.unwrap_or(false) {
        let prac_row =
            sqlx::query("SELECT id FROM practitioner WHERE cabinet_id = $1 AND user_id = $2")
                .bind(claims.cabinet_id)
                .bind(claims.sub)
                .fetch_optional(&mut *tx)
                .await
                .map_err(|_| AppError::Internal)?
                .ok_or(AppError::Forbidden)?;
        Some(prac_row.try_get("id").map_err(|_| AppError::Internal)?)
    } else {
        None
    };

    let items_json = serde_json::to_value(&body.items).map_err(|_| AppError::ValidationError)?;

    let tmpl_row = sqlx::query(
        "INSERT INTO prescription_template (cabinet_id, practitioner_id, label, items) \
         VALUES ($1, $2, $3, $4) \
         RETURNING id",
    )
    .bind(claims.cabinet_id)
    .bind(practitioner_id)
    .bind(body.label.trim())
    .bind(&items_json)
    .fetch_one(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?;

    let template_id: Uuid = tmpl_row.try_get("id").map_err(|_| AppError::Internal)?;

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        template_id = %template_id,
        "prescription template created"
    );

    Ok((
        StatusCode::CREATED,
        Json(CreatePrescriptionTemplateResponse { template_id }),
    ))
}

// ── POST /v1/cabinet/prescriptions/:id/apply-template ───────────────────────

/// Body de `POST /v1/cabinet/prescriptions/:id/apply-template`.
#[derive(Deserialize)]
pub struct ApplyTemplateBody {
    pub template_id: Uuid,
}

/// Réponse de `POST /v1/cabinet/prescriptions/:id/apply-template`.
#[derive(Serialize)]
pub struct ApplyTemplateResponse {
    pub prescription_id: Uuid,
    pub items_created: usize,
}

/// `POST /v1/cabinet/prescriptions/:id/apply-template` — préremplit un
/// brouillon avec les lignes d'un modèle.
///
/// - Auth JWT pro `practitioner`/`admin` requis.
/// - Ordonnance inexistante/hors cabinet → 404.
/// - Ordonnance pas au statut `draft` (déjà signée/envoyée) → 409
///   `invalid_status` : appliquer un modèle n'a de sens qu'avant signature.
/// - Modèle inexistant OU appartenant à un AUTRE cabinet (privé, invisible
///   via RLS) → 404 — c'est le même comportement pour les deux cas, RLS
///   fail-closed ne les distingue pas et l'API ne doit pas les distinguer
///   non plus (éviter de révéler l'existence d'un modèle privé d'un autre
///   cabinet).
/// - Ajoute une `prescription_item` par ligne du modèle (`items` jsonb).
/// - Retourne `200 { prescription_id, items_created }`.
pub async fn apply_prescription_template(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Path(prescription_id): Path<Uuid>,
    Json(body): Json<ApplyTemplateBody>,
) -> Result<Json<ApplyTemplateResponse>, AppError> {
    let mut tx = state.db.begin().await.map_err(|_| AppError::Internal)?;

    sqlx::query("SELECT set_config('app.current_cabinet_id', $1, true)")
        .bind(claims.cabinet_id.to_string())
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;

    let presc_row = sqlx::query(
        "SELECT status FROM prescription \
         WHERE id = $1 AND cabinet_id = $2 AND deleted_at IS NULL",
    )
    .bind(prescription_id)
    .bind(claims.cabinet_id)
    .fetch_optional(&mut *tx)
    .await
    .map_err(|_| AppError::Internal)?
    .ok_or(AppError::NotFound)?;

    let status: String = presc_row
        .try_get("status")
        .map_err(|_| AppError::Internal)?;
    if status != "draft" {
        return Err(AppError::InvalidStatus);
    }

    // RLS (tenant_isolation OR global_template_read) rend invisible tout
    // modèle privé d'un autre cabinet : même 404 que "n'existe pas".
    let tmpl_row = sqlx::query("SELECT items FROM prescription_template WHERE id = $1")
        .bind(body.template_id)
        .fetch_optional(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?
        .ok_or(AppError::NotFound)?;

    let items_json: serde_json::Value =
        tmpl_row.try_get("items").map_err(|_| AppError::Internal)?;
    let items: Vec<TemplateItemInput> =
        serde_json::from_value(items_json).map_err(|_| AppError::Internal)?;

    for item in &items {
        sqlx::query(
            "INSERT INTO prescription_item \
             (cabinet_id, prescription_id, label, form, posology, duration, quantity) \
             VALUES ($1, $2, $3, $4, $5, $6, $7)",
        )
        .bind(claims.cabinet_id)
        .bind(prescription_id)
        .bind(&item.label)
        .bind(&item.form)
        .bind(&item.posology)
        .bind(&item.duration)
        .bind(&item.quantity)
        .execute(&mut *tx)
        .await
        .map_err(|_| AppError::Internal)?;
    }

    tx.commit().await.map_err(|_| AppError::Internal)?;

    tracing::info!(
        cabinet_id = %claims.cabinet_id,
        user_id = %claims.sub,
        prescription_id = %prescription_id,
        template_id = %body.template_id,
        items_created = items.len(),
        "prescription template applied"
    );

    Ok(Json(ApplyTemplateResponse {
        prescription_id,
        items_created: items.len(),
    }))
}
