//! `GET /v1/ccam/acts` — recherche dans le référentiel CCAM (#3226).
//!
//! #4112 : quand `q` est vide, les actes favoris du praticien appelant
//! (`practitioner_favorite_act`, migration 0181) remontent en tête de
//! liste, triés par `position` — seulement quand `q` est vide, une
//! recherche texte reste un filtre pur (pas de biais favoris qui masquerait
//! un résultat pertinent hors favoris).
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
/// `pub(crate)` : réutilisée par `consultation_acts::add_consultation_act`
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
