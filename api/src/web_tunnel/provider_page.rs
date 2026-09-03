//! `GET /:slug` (ex. `/dr-amelie-rousseau-dentiste-paris`) — fiche
//! praticien SSR (#5356). Résout le slug en `provider_id` par préfixe de nom
//! (le nom du praticien est toujours le préfixe du slug produit par
//! [`slug_for`], utilisé aussi bien ici que par les cartes de la page de
//! recherche) puis appelle `marketplace::get_provider`, la MÊME fonction que
//! l'API publique `GET /v1/providers/:id` — aucune logique dupliquée
//! (#5355).

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use uuid::Uuid;

use crate::marketplace::{
    get_provider, search_providers, search_slots, SearchProvidersQuery, SlotRef,
};
use crate::AppState;

use super::html::{escape, page};
use super::search_page::group_slots_by_day;
use super::slug::slugify;

/// Ex. `("Dr Amélie Rousseau", Some("Chirurgien-dentiste"), Some("Paris"))`
/// → `"dr-amelie-rousseau-chirurgien-dentiste-paris"`.
pub fn slug_for(display_name: &str, specialty: Option<&str>, city: Option<&str>) -> String {
    let mut parts = vec![display_name.to_string()];
    if let Some(s) = specialty {
        parts.push(s.to_string());
    }
    if let Some(c) = city {
        parts.push(c.to_string());
    }
    slugify(&parts.join(" "))
}

/// 1er mot significatif du slug (après un éventuel `dr`) — un seul mot pour
/// matcher la recherche par sous-chaîne de `search_providers` (pas de
/// tokenisation côté SQL, cf. sa doc).
fn search_term_from_slug(slug: &str) -> Option<&str> {
    slug.split('-').find(|w| *w != "dr" && !w.is_empty())
}

pub async fn provider_page(State(state): State<AppState>, Path(slug): Path<String>) -> Response {
    let Some(term) = search_term_from_slug(&slug) else {
        return not_found();
    };

    let params = SearchProvidersQuery {
        q: Some(term.to_string()),
        specialty: None,
        near: None,
        place: None,
        radius_km: None,
        bbox: None,
        sector: None,
        teleconsult: None,
        pmr: None,
        languages: None,
        accepts_new: None,
        available: None,
        tiers_payant: None,
        sort: None,
        page: Some(1),
        per_page: Some(50),
        provider_id: None,
        date: None,
    };

    let candidates = match search_providers(State(state.clone()), Query(params)).await {
        Ok(Json(resp)) => resp.data,
        Err(_) => Vec::new(),
    };

    let Some(matched) = candidates
        .into_iter()
        .find(|p| slug.starts_with(&slugify(&p.display_name)))
    else {
        return not_found();
    };

    let profile = match get_provider(State(state.clone()), Path(matched.provider_id)).await {
        Ok(Json(profile)) => profile,
        Err(_) => return not_found(),
    };

    // Agenda de la fiche (#6318) : `search_slots`, MÊME fonction que l'API
    // publique `/v1/search/slots`, restreinte à ce praticien via
    // `provider_id` — aucune requête de créneaux dupliquée (#5355). Cette
    // page EST la destination du lien de débord de la carte de recherche,
    // donc tous les jours à créneaux sont montrés, sans grille tronquée.
    let slots_params = SearchProvidersQuery {
        q: None,
        specialty: None,
        near: None,
        place: None,
        radius_km: None,
        bbox: None,
        sector: None,
        teleconsult: None,
        pmr: None,
        languages: None,
        accepts_new: None,
        available: None,
        tiers_payant: None,
        sort: None,
        page: Some(1),
        per_page: Some(1),
        provider_id: Some(matched.provider_id.to_string()),
        date: None,
    };
    let slots = match search_slots(State(state), Query(slots_params)).await {
        Ok(Json(resp)) => resp
            .data
            .into_iter()
            .find(|item| item.provider_id == matched.provider_id)
            .map(|item| item.slots)
            .unwrap_or_default(),
        Err(_) => Vec::new(),
    };
    let agenda = render_agenda(matched.provider_id, &slots);

    let city = profile
        .address
        .as_ref()
        .and_then(|a| a.get("ville"))
        .and_then(|v| v.as_str())
        .unwrap_or_default();

    let h1 = profile.display_name.clone();
    let subtitle = [profile.profession.clone(), profile.specialty.clone()]
        .into_iter()
        .flatten()
        .collect::<Vec<_>>()
        .join(" · ");

    let context = if !city.is_empty() {
        format!(
            "{name} exerce{sector} à {city}{tp}.",
            name = escape(&h1),
            sector = profile
                .sector
                .as_deref()
                .map(|s| format!(" en secteur {}", escape(s)))
                .unwrap_or_default(),
            city = escape(city),
            tp = if profile.tiers_payant.unwrap_or(false) {
                " et pratique le tiers payant"
            } else {
                ""
            },
        )
    } else {
        format!("Profil du praticien {}.", escape(&h1))
    };

    let title = format!("{h1} — Nubia");
    let body = format!(
        r#"<h1>{h1}</h1>
<p class="muted">{subtitle}</p>
<div class="context">
  <p>{context}</p>
</div>
{agenda}
<p><a href="/appointments?providerId={provider_id}">Prendre rendez-vous</a></p>"#,
        h1 = escape(&h1),
        subtitle = escape(&subtitle),
        provider_id = profile.provider_id,
    );

    page(&title, &body).into_response()
}

/// Agenda de la fiche praticien : tous les jours à créneaux ouverts,
/// groupés comme `_SlotsByDay` (`modify_rdv_page.dart`) — repli explicite
/// (pas un état vide silencieux) quand le praticien n'a aucun créneau en
/// ligne (#6318).
fn render_agenda(provider_id: Uuid, slots: &[SlotRef]) -> String {
    if slots.is_empty() {
        return r#"<div class="nosl">
  <p class="muted">Aucun créneau en ligne pour ce praticien pour le moment.</p>
</div>"#
            .to_string();
    }

    let days_html = group_slots_by_day(slots)
        .iter()
        .map(|day| {
            let chips = day
                .slots
                .iter()
                .map(|(hhmm, slot_id)| {
                    format!(
                        r#"<a class="chip" href="/appointments?providerId={provider_id}&amp;slotId={slot_id}">{hhmm}</a>"#,
                    )
                })
                .collect::<Vec<_>>()
                .join("");
            format!(
                r#"<div class="day"><span class="dlabel">{label}</span>{chips}</div>"#,
                label = escape(&day.label),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(r#"<div class="slots">{days_html}</div>"#)
}

fn not_found() -> Response {
    let body = r#"<h1>Praticien introuvable</h1>
<div class="context">
  <p>Ce profil n'existe pas ou n'est plus référencé dans l'annuaire Nubia.</p>
</div>"#;
    (
        StatusCode::NOT_FOUND,
        page("Praticien introuvable — Nubia", body),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slug_for_matches_the_mockup_pattern() {
        assert_eq!(
            slug_for(
                "Dr Amélie Rousseau",
                Some("Chirurgien-dentiste"),
                Some("Paris")
            ),
            "dr-amelie-rousseau-chirurgien-dentiste-paris"
        );
    }

    #[test]
    fn generated_slug_starts_with_name_only_slug() {
        let full = slug_for("Dr Hugo Marin", Some("Implantologie"), Some("Lyon"));
        let name_only = slugify("Dr Hugo Marin");
        assert!(full.starts_with(&name_only));
    }

    #[test]
    fn search_term_skips_leading_dr_token() {
        assert_eq!(
            search_term_from_slug("dr-amelie-rousseau-dentiste-paris"),
            Some("amelie")
        );
    }
}
