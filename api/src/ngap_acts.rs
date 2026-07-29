//! `GET /v1/ngap/acts` — recherche dans le référentiel NGAP (#4053).
//!
//! Symétrique à `search_ccam_acts` (`api/src/consultations.rs`) : même
//! contrat (query `q`, limite 25, normalisation accents/casse), table
//! différente (`ngap_act`, migration 0159). Placé dans son propre module
//! plutôt que dans `consultations.rs` (déjà 1182 lignes, au-dessus du
//! plafond absolu de 700 lignes — CLAUDE.md — un refactor de ce fichier est
//! un préalable obligatoire à tout nouvel ajout, donc hors scope ici).

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un acte du référentiel NGAP (catalogue dentaire).
#[derive(Serialize)]
pub struct NgapActItem {
    pub code: String,
    pub lettre_cle: String,
    pub coefficient: f64,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tarif_cents: Option<i32>,
}

/// Réponse de `GET /v1/ngap/acts`.
#[derive(Serialize)]
pub struct NgapActsResponse {
    pub data: Vec<NgapActItem>,
}

/// Query de `GET /v1/ngap/acts`.
#[derive(Deserialize)]
pub struct NgapActsQuery {
    /// Filtre plein-texte sur le code OU le libellé (insensible à la casse).
    pub q: Option<String>,
}

/// `GET /v1/ngap/acts?q=` — recherche dans le référentiel NGAP (#4053).
///
/// Praticien uniquement (contexte clinique) — secrétaire → 403.
/// Référentiel national (pas de donnée patient, pas de RLS). `q` filtre code
/// et libellé ; sans `q`, retourne le début du catalogue. Limité à 25 lignes.
pub async fn search_ngap_acts(
    State(state): State<AppState>,
    _claims: ProPractitionerClaims,
    Query(query): Query<NgapActsQuery>,
) -> Result<Json<NgapActsResponse>, AppError> {
    // #4397 : NUL byte non filtré → 500 au bind.
    if let Some(q) = query.q.as_deref() {
        crate::text_validation::reject_nul_byte(q)?;
    }
    let q = query.q.as_deref().map(|s| s.trim().to_lowercase());

    let rows = sqlx::query(
        "SELECT code, lettre_cle, coefficient::double precision AS coefficient, \
                label, tarif_cents FROM ngap_act \
         WHERE active = true \
           AND ($1::text IS NULL \
                OR translate(lower(label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                     LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                OR lower(code) LIKE '%' || $1 || '%') \
         ORDER BY label \
         LIMIT 25",
    )
    .bind(q.as_deref())
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            Ok(NgapActItem {
                code: r.try_get("code").map_err(|_| AppError::Internal)?,
                lettre_cle: r.try_get("lettre_cle").map_err(|_| AppError::Internal)?,
                coefficient: r.try_get("coefficient").map_err(|_| AppError::Internal)?,
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                tarif_cents: r.try_get("tarif_cents").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(NgapActsResponse { data }))
}
