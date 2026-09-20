//! `GET /v1/medication-references` — recherche dans le référentiel
//! médicament (DCI, forme galénique, classe thérapeutique) pour la
//! composition d'ordonnance (#7433).
//!
//! Root cause de #7433 : le champ de recherche front existait déjà
//! (#4987/#6104, `ordonnance_new_page.dart`) mais n'avait aucune source de
//! données — ni endpoint, ni table. Symétrique à
//! `ccam_acts::search_ccam_acts` (migration 0119) mais sans les mécaniques
//! favoris/suggestion-dent/tarif, sans objet ici : juste une recherche
//! substring sur la DCI, insensible à la casse et aux accents.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use sqlx::Row;
use uuid::Uuid;

use crate::{
    auth::{AppError, ProPractitionerClaims},
    AppState,
};

/// Un produit du référentiel médicament.
#[derive(Serialize)]
pub struct MedicationReferenceItem {
    pub id: Uuid,
    pub dci: String,
    pub galenic_form: String,
    pub therapeutic_class: String,
}

/// Réponse de `GET /v1/medication-references`.
#[derive(Serialize)]
pub struct MedicationReferencesResponse {
    pub data: Vec<MedicationReferenceItem>,
}

/// Query de `GET /v1/medication-references`.
#[derive(Deserialize)]
pub struct MedicationReferencesQuery {
    pub q: Option<String>,
}

/// `GET /v1/medication-references?q=` — recherche dans le référentiel
/// médicament (#7433).
///
/// Praticien uniquement (contexte de prescription) — secrétaire → 403.
/// Référentiel national (pas de donnée patient, pas de RLS). `q` filtre la
/// DCI (substring, insensible casse/accents) ; absent ou < 2 caractères
/// (saisis ou après trim) → liste vide, même contrat que le champ front
/// (`_AddItemSearchField`/`_MedicationSearchField`, maquette design-v2 :
/// la recherche ne se déclenche qu'à partir de 2 caractères). Limité à 20
/// lignes.
pub async fn search_medication_references(
    State(state): State<AppState>,
    _claims: ProPractitionerClaims,
    Query(query): Query<MedicationReferencesQuery>,
) -> Result<Json<MedicationReferencesResponse>, AppError> {
    let q = query.q.as_deref().map(|s| s.trim().to_lowercase());
    if q.as_deref().map(|s| s.chars().count()).unwrap_or(0) < 2 {
        return Ok(Json(MedicationReferencesResponse { data: Vec::new() }));
    }
    let q = q.expect("longueur >= 2 déjà vérifiée, donc q est bien Some");
    // #4397 (ccam_acts) : NUL byte non filtré → 500 au bind.
    crate::text_validation::reject_nul_byte(&q)?;

    let rows = sqlx::query(
        "SELECT id, dci, galenic_form, therapeutic_class \
         FROM medication_reference \
         WHERE active = true \
           AND translate(lower(dci), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
         ORDER BY dci \
         LIMIT 20",
    )
    .bind(&q)
    .fetch_all(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;

    let data = rows
        .into_iter()
        .map(|r| {
            Ok(MedicationReferenceItem {
                id: r.try_get("id").map_err(|_| AppError::Internal)?,
                dci: r.try_get("dci").map_err(|_| AppError::Internal)?,
                galenic_form: r.try_get("galenic_form").map_err(|_| AppError::Internal)?,
                therapeutic_class: r
                    .try_get("therapeutic_class")
                    .map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(MedicationReferencesResponse { data }))
}
