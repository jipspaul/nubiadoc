//! Tarification indicative des visites infirmières à domicile (#6117).
//!
//! `POST /v1/account/visit-requests/estimate` : prix affiché AVANT que le
//! patient s'engage sur une demande. Le même calcul est appliqué à la
//! création (`requests::create_visit_request`) pour que le prix affiché soit
//! celui réellement appliqué à la visite — pas de barème parallèle.
//!
//! Barème forfaitaire en dur (MVP), même approche que
//! `requests::ALLOWED_ACTS` : un catalogue configurable viendra plus tard.

use axum::Json;
use serde::{Deserialize, Serialize};

use crate::auth::{AppError, PatientAccountClaims};
use crate::nurse::requests::ALLOWED_ACTS;

/// Frais de déplacement forfaitaire (visite à domicile), en centimes.
const CALLOUT_FEE_CENTS: i32 = 2500;

/// Tarif par acte, en centimes — même ordre que `ALLOWED_ACTS`.
const ACT_PRICE_CENTS: &[i32] = &[
    2000, // prise_de_sang
    1500, // pansement
    1800, // injection
    2500, // perfusion
    2200, // toilette
    2000, // surveillance
];

/// Calcule le prix estimé (frais de déplacement + somme des actes demandés).
/// Actes hors `ALLOWED_ACTS` ignorés ici (validés en amont par le caller — 422).
pub(crate) fn estimate_price_cents(requested_acts: &[String]) -> i32 {
    let acts_total: i32 = requested_acts
        .iter()
        .filter_map(|a| ALLOWED_ACTS.iter().position(|x| x == a))
        .map(|idx| ACT_PRICE_CENTS[idx])
        .sum();
    CALLOUT_FEE_CENTS + acts_total
}

/// Corps de `POST /v1/account/visit-requests/estimate`.
#[derive(Deserialize)]
pub struct EstimateVisitBody {
    pub lat: f64,
    pub lng: f64,
    #[serde(default)]
    pub requested_acts: Vec<String>,
}

/// Réponse de `POST /v1/account/visit-requests/estimate`.
#[derive(Serialize)]
pub struct EstimateVisitResponse {
    pub estimated_price_cents: i32,
}

/// `POST /v1/account/visit-requests/estimate` — prix indicatif avant demande
/// (#6117). lat/lng réservés à une tarification par zone géographique future
/// (pas utilisés par le barème forfaitaire v1). Acte inconnu → 422 (même
/// validation qu'à la création, `requests::create_visit_request`).
pub async fn estimate_visit_price(
    _claims: PatientAccountClaims,
    Json(body): Json<EstimateVisitBody>,
) -> Result<Json<EstimateVisitResponse>, AppError> {
    tracing::debug!(
        lat = body.lat,
        lng = body.lng,
        "visit price estimate requested"
    );
    if !body
        .requested_acts
        .iter()
        .all(|a| ALLOWED_ACTS.contains(&a.as_str()))
    {
        return Err(AppError::ValidationError);
    }
    Ok(Json(EstimateVisitResponse {
        estimated_price_cents: estimate_price_cents(&body.requested_acts),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn no_acts_is_just_the_callout_fee() {
        assert_eq!(estimate_price_cents(&[]), CALLOUT_FEE_CENTS);
    }

    #[test]
    fn known_acts_add_up_to_the_callout_fee() {
        let acts = vec!["prise_de_sang".to_string(), "pansement".to_string()];
        assert_eq!(estimate_price_cents(&acts), CALLOUT_FEE_CENTS + 2000 + 1500);
    }

    #[test]
    fn unknown_acts_are_ignored() {
        let acts = vec!["acte_inconnu".to_string()];
        assert_eq!(estimate_price_cents(&acts), CALLOUT_FEE_CENTS);
    }
}
