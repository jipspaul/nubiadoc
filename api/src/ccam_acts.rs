//! `GET /v1/ccam/acts` — recherche dans le référentiel CCAM (#3226).
//!
//! Extrait de `consultations.rs` (refactor de taille, cf. #4056 / CLAUDE.md
//! plafond 700 lignes) — module autonome, mêmes handlers/contrats, aucun
//! changement fonctionnel. Symétrique à `ngap_acts.rs`.

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

/// Un acte du référentiel CCAM (catalogue dentaire).
#[derive(Serialize)]
pub struct CcamActItem {
    pub code: String,
    pub label: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tarif_cents: Option<i32>,
}

/// Réponse de `GET /v1/ccam/acts`.
#[derive(Serialize)]
pub struct CcamActsResponse {
    pub data: Vec<CcamActItem>,
}

/// Query de `GET /v1/ccam/acts`.
#[derive(Deserialize)]
pub struct CcamActsQuery {
    /// Filtre plein-texte sur le code OU le libellé (insensible à la casse).
    pub q: Option<String>,
}

/// `GET /v1/ccam/acts?q=` — recherche dans le référentiel CCAM (#3226).
///
/// Praticien uniquement (contexte clinique) — secrétaire → 403.
/// Référentiel national (pas de donnée patient, pas de RLS). `q` filtre code
/// et libellé ; sans `q`, retourne le début du catalogue. Limité à 25 lignes.
pub async fn search_ccam_acts(
    State(state): State<AppState>,
    _claims: ProPractitionerClaims,
    Query(query): Query<CcamActsQuery>,
) -> Result<Json<CcamActsResponse>, AppError> {
    // q normalisée (trim + minuscules) ; la normalisation des accents se fait
    // en SQL via translate() côté libellé ET côté motif, pour matcher
    // « detartrage » sur « Détartrage ».
    let q = query.q.as_deref().map(|s| s.trim().to_lowercase());

    let rows = sqlx::query(
        "SELECT code, label, tarif_cents FROM ccam_act \
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
            Ok(CcamActItem {
                code: r.try_get("code").map_err(|_| AppError::Internal)?,
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                tarif_cents: r.try_get("tarif_cents").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(CcamActsResponse { data }))
}
