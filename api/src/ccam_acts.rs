//! `GET /v1/ccam/acts` — recherche dans le référentiel CCAM (#3226).
//!
//! #4112 : quand `q` est vide, les actes favoris du praticien appelant
//! (`practitioner_favorite_act`, migration 0181) remontent en tête de
//! liste, triés par `position` — seulement quand `q` est vide, une
//! recherche texte reste un filtre pur (pas de biais favoris qui masquerait
//! un résultat pertinent hors favoris).
//!
//! #4118 : `tooth` (numéro FDI, ex. "26") — quand `q` est vide, les codes
//! CCAM les plus utilisés par CE praticien sur des dents de même type
//! (incisive/canine/prémolaire/molaire, déduit du 2e chiffre FDI) remontent
//! juste après les favoris. Historique lu dans `consultation_act` (pas de
//! nouvelle table) : agrégation faite côté Rust plutôt qu'en SQL sur le
//! dernier chiffre de `tooth`, la correspondance chiffre→type diffère entre
//! denture permanente (quadrants 1-4) et denture de lait (quadrants 5-8),
//! trop de cas particuliers pour une expression SQL lisible.
//!
//! #4056 : sélectionne le tarif applicable (`applicable_tariff_cents`) selon
//! le secteur conventionnel du praticien appelant — OPTAM → `optam_cents`,
//! sinon `secteur1_cents` (repli sur `tarif_cents` si non classifié, cf.
//! `ccam_act` #4054 : catalogue partiel). Adhésion OPTAM lue depuis
//! `practitioner.conventions` (jsonb, colonne posée par la migration 0002,
//! jusqu'ici jamais lue/écrite — `{"optam": true}` ; absente ou `false` par
//! défaut). `panier_sante` passthrough (`null` si non classifié).
//!
//! Extrait de `consultations.rs` (refactor de taille, cf. #4056 / CLAUDE.md
//! plafond 700 lignes) — module autonome, symétrique à `ngap_acts.rs`.

use axum::{
    extract::{Query, State},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::Value as JsonValue;
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
    /// Tarif applicable au praticien appelant (#4056) : `optam_cents` s'il a
    /// adhéré à l'OPTAM, sinon `secteur1_cents` — repli sur `tarif_cents` si
    /// la ligne n'est pas encore classifiée (#4054/#4055). `null` seulement
    /// si aucune des trois colonnes n'a de valeur.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub applicable_tariff_cents: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub panier_sante: Option<String>,
}

/// `optam_cents` si `is_optam`, sinon `secteur1_cents` — repli sur
/// `tarif_cents` dans les deux cas si la colonne préférée est `NULL` (acte
/// non classifié, cf. #4054/#4055).
///
/// `pub(crate)` : réutilisée par `consultation_act_create::add_consultation_act`
/// (#4162) pour l'avertissement de sous-cotation — même notion de "tarif
/// applicable à CE praticien" que celle déjà exposée par `GET /v1/ccam/acts`.
pub(crate) fn select_applicable_tariff(
    is_optam: bool,
    tarif_cents: Option<i32>,
    secteur1_cents: Option<i32>,
    optam_cents: Option<i32>,
) -> Option<i32> {
    if is_optam {
        optam_cents.or(secteur1_cents).or(tarif_cents)
    } else {
        secteur1_cents.or(tarif_cents)
    }
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
    /// Numéro de dent FDI (#4118) — surface les codes les plus utilisés par
    /// ce praticien sur des dents de même type (voir doc de module).
    pub tooth: Option<String>,
}

/// Type de dent déduit du 2e chiffre FDI (position dans le quadrant).
/// Le 1er chiffre distingue denture permanente (1-4) de denture de lait
/// (5-8) — la correspondance position→type diffère entre les deux (ex. « 4 »
/// = prémolaire en permanent, mais 1re molaire de lait en denture primaire).
/// `None` si `tooth` n'est pas exactement 2 chiffres FDI valides.
fn fdi_tooth_type(tooth: &str) -> Option<&'static str> {
    let tooth = tooth.trim();
    if tooth.len() != 2 {
        return None;
    }
    let mut chars = tooth.chars();
    let quadrant = chars.next()?.to_digit(10)?;
    let position = chars.next()?.to_digit(10)?;
    if !(1..=8).contains(&quadrant) {
        return None;
    }
    if quadrant >= 5 {
        // Denture de lait (quadrants 5-8) : positions 1-5 seulement.
        match position {
            1 | 2 => Some("incisive"),
            3 => Some("canine"),
            4 | 5 => Some("molaire"),
            _ => None,
        }
    } else {
        match position {
            1 | 2 => Some("incisive"),
            3 => Some("canine"),
            4 | 5 => Some("premolaire"),
            6..=8 => Some("molaire"),
            _ => None,
        }
    }
}

/// `GET /v1/ccam/acts?q=` — recherche dans le référentiel CCAM (#3226).
///
/// Praticien uniquement (contexte clinique) — secrétaire → 403.
/// Référentiel national (pas de donnée patient, pas de RLS). `q` filtre code
/// et libellé ; sans `q`, retourne le début du catalogue. Limité à 25 lignes.
pub async fn search_ccam_acts(
    State(state): State<AppState>,
    claims: ProPractitionerClaims,
    Query(query): Query<CcamActsQuery>,
) -> Result<Json<CcamActsResponse>, AppError> {
    // q normalisée (trim + minuscules) ; la normalisation des accents se fait
    // en SQL via translate() côté libellé ET côté motif, pour matcher
    // « detartrage » sur « Détartrage ».
    let q = query.q.as_deref().map(|s| s.trim().to_lowercase());

    // Adhésion OPTAM du praticien appelant (#4056) — `practitioner.conventions`
    // jsonb, `{"optam": true}` ; absente/false par défaut (non-adhérent).
    // `id` récupéré dans la même requête pour les favoris (#4112).
    let practitioner = sqlx::query(
        "SELECT id, conventions FROM practitioner WHERE user_id = $1 AND cabinet_id = $2",
    )
    .bind(claims.sub)
    .bind(claims.cabinet_id)
    .fetch_optional(&state.db)
    .await
    .map_err(|_| AppError::Internal)?;
    let practitioner_id: Option<uuid::Uuid> = practitioner
        .as_ref()
        .map(|r| r.try_get("id"))
        .transpose()
        .map_err(|_| AppError::Internal)?;
    let conventions: Option<JsonValue> = practitioner
        .map(|r| r.try_get("conventions"))
        .transpose()
        .map_err(|_| AppError::Internal)?;
    let is_optam = conventions
        .as_ref()
        .and_then(|c| c.get("optam"))
        .and_then(JsonValue::as_bool)
        .unwrap_or(false);

    let mut rows = Vec::new();
    if q.is_none() {
        if let Some(practitioner_id) = practitioner_id {
            let favorite_rows = sqlx::query(
                "SELECT c.code, c.label, c.tarif_cents, c.secteur1_cents, c.optam_cents, c.panier_sante \
                 FROM practitioner_favorite_act f \
                 JOIN ccam_act c ON c.code = f.ccam_code AND c.active = true \
                 WHERE f.practitioner_id = $1 \
                 ORDER BY f.position \
                 LIMIT 25",
            )
            .bind(practitioner_id)
            .fetch_all(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;
            rows.extend(favorite_rows);
        }
    }

    // Suggestion contextuelle par type de dent (#4118) — juste après les
    // favoris, seulement quand q est vide (même garde que #4112 : une
    // recherche texte reste un filtre pur).
    if q.is_none() {
        if let (Some(practitioner_id), Some(target_type)) = (
            practitioner_id,
            query.tooth.as_deref().and_then(fdi_tooth_type),
        ) {
            let existing_codes: Vec<String> = rows
                .iter()
                .map(|r| r.try_get::<String, _>("code"))
                .collect::<Result<_, _>>()
                .map_err(|_| AppError::Internal)?;

            let history = sqlx::query(
                "SELECT tooth, ccam_code FROM consultation_act \
                 WHERE practitioner_id = $1 AND cabinet_id = $2 AND tooth IS NOT NULL",
            )
            .bind(practitioner_id)
            .bind(claims.cabinet_id)
            .fetch_all(&state.db)
            .await
            .map_err(|_| AppError::Internal)?;

            let mut counts: std::collections::HashMap<String, i64> =
                std::collections::HashMap::new();
            for row in history {
                let tooth: Option<String> = row.try_get("tooth").map_err(|_| AppError::Internal)?;
                let code: String = row.try_get("ccam_code").map_err(|_| AppError::Internal)?;
                if tooth.as_deref().and_then(fdi_tooth_type) == Some(target_type)
                    && !existing_codes.contains(&code)
                {
                    *counts.entry(code).or_insert(0) += 1;
                }
            }

            let mut ranked: Vec<(String, i64)> = counts.into_iter().collect();
            ranked.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));
            let top_codes: Vec<String> = ranked
                .into_iter()
                .take((25 - rows.len() as i64).max(0) as usize)
                .map(|(code, _)| code)
                .collect();

            if !top_codes.is_empty() {
                let suggestion_rows = sqlx::query(
                    "SELECT code, label, tarif_cents, secteur1_cents, optam_cents, panier_sante \
                     FROM ccam_act WHERE code = ANY($1) AND active = true",
                )
                .bind(&top_codes)
                .fetch_all(&state.db)
                .await
                .map_err(|_| AppError::Internal)?;
                // Réordonne selon top_codes (fetch_all ne garantit pas l'ordre de ANY()).
                let mut by_code: std::collections::HashMap<String, sqlx::postgres::PgRow> =
                    suggestion_rows
                        .into_iter()
                        .map(|r| (r.get::<String, _>("code"), r))
                        .collect();
                for code in &top_codes {
                    if let Some(row) = by_code.remove(code) {
                        rows.push(row);
                    }
                }
            }
        }
    }

    let remaining = 25 - rows.len() as i64;
    if remaining > 0 {
        let favorite_codes: Vec<String> = rows
            .iter()
            .map(|r| r.try_get::<String, _>("code"))
            .collect::<Result<_, _>>()
            .map_err(|_| AppError::Internal)?;

        let more_rows = sqlx::query(
            "SELECT code, label, tarif_cents, secteur1_cents, optam_cents, panier_sante \
             FROM ccam_act \
             WHERE active = true \
               AND NOT (code = ANY($2)) \
               AND ($1::text IS NULL \
                    OR translate(lower(label), 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') \
                         LIKE '%' || translate($1, 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn') || '%' \
                    OR lower(code) LIKE '%' || $1 || '%') \
             ORDER BY label \
             LIMIT $3",
        )
        .bind(q.as_deref())
        .bind(&favorite_codes)
        .bind(remaining)
        .fetch_all(&state.db)
        .await
        .map_err(|_| AppError::Internal)?;
        rows.extend(more_rows);
    }

    let data = rows
        .into_iter()
        .map(|r| {
            let tarif_cents: Option<i32> =
                r.try_get("tarif_cents").map_err(|_| AppError::Internal)?;
            let secteur1_cents: Option<i32> = r
                .try_get("secteur1_cents")
                .map_err(|_| AppError::Internal)?;
            let optam_cents: Option<i32> =
                r.try_get("optam_cents").map_err(|_| AppError::Internal)?;
            Ok(CcamActItem {
                code: r.try_get("code").map_err(|_| AppError::Internal)?,
                label: r.try_get("label").map_err(|_| AppError::Internal)?,
                tarif_cents,
                applicable_tariff_cents: select_applicable_tariff(
                    is_optam,
                    tarif_cents,
                    secteur1_cents,
                    optam_cents,
                ),
                panier_sante: r.try_get("panier_sante").map_err(|_| AppError::Internal)?,
            })
        })
        .collect::<Result<Vec<_>, AppError>>()?;

    Ok(Json(CcamActsResponse { data }))
}
