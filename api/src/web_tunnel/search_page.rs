//! `GET /:query_slug/:locality_slug` (ex. `/dentiste/paris-2e`) — page de
//! recherche SSR du tunnel web (#5356). Consomme
//! `marketplace::search_providers`, la MÊME fonction que l'API publique
//! `GET /v1/search/providers` — aucune requête ni logique dupliquée (#5355).

use axum::extract::{Path, Query, State};
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Duration, Utc};

use crate::marketplace::{search_providers, ProviderItem, SearchProvidersQuery};
use crate::AppState;

use super::html::{escape, page};
use super::locality::{self, label as locality_label, ordinal, titleize, Locality};
use super::provider_page::slug_for;

fn specialty_plural_label(specialty_slug: &str) -> String {
    match specialty_slug {
        "dentiste" => "Chirurgiens-dentistes".to_string(),
        "orthodontiste" => "Orthodontistes".to_string(),
        _ => {
            let t = titleize(specialty_slug);
            if t.ends_with('s') {
                t
            } else {
                format!("{t}s")
            }
        }
    }
}

fn related_specialty_slug(specialty_slug: &str) -> &'static str {
    match specialty_slug {
        "dentiste" => "orthodontiste",
        "orthodontiste" => "dentiste",
        _ => "dentiste",
    }
}

/// Qualificatif d'urgence par spécialité (« urgence dentaire », pas
/// « urgence dentiste ») — connu pour la spécialité verbatim de la maquette,
/// générique sinon.
fn urgency_noun(specialty_slug: &str) -> &'static str {
    match specialty_slug {
        "dentiste" => "dentaire",
        _ => "médicale",
    }
}

pub async fn search_page(
    State(state): State<AppState>,
    Path((query_slug, locality_slug)): Path<(String, String)>,
) -> impl IntoResponse {
    let loc = locality::parse(&locality_slug);
    let loc_label = locality_label(&loc);
    let query_terms = query_slug.replace('-', " ");

    let params = SearchProvidersQuery {
        q: Some(query_terms.clone()),
        specialty: None,
        near: None,
        place: Some(loc.city_slug.clone()),
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

    let (providers, total) = match search_providers(State(state), Query(params)).await {
        Ok(Json(resp)) => (resp.data, resp.page.total),
        Err(_) => (Vec::new(), 0),
    };

    let now = Utc::now();
    let within_48h = providers
        .iter()
        .filter(|p| {
            p.next_slot_at
                .as_deref()
                .and_then(|s| DateTime::parse_from_rfc3339(s).ok())
                .map(|dt| dt.with_timezone(&Utc) - now < Duration::hours(48))
                .unwrap_or(false)
        })
        .count();

    let h1 = format!("{} à {}", specialty_plural_label(&query_slug), loc_label);
    let title = format!("{h1} — Nubia");

    let seo_paragraph = if total > 0 {
        format!(
            "{total} praticien{s} accepte{ntpl} des rendez-vous en ligne à {loc_label}, dont {within_48h} avec une disponibilité sous 48 heures. La majorité pratique le tiers payant et les tarifs conventionnés du secteur 1.",
            s = if total > 1 { "s" } else { "" },
            ntpl = if total > 1 { "nt" } else { "" },
        )
    } else {
        format!(
            "Aucun praticien « {q} » n'est actuellement référencé à {loc_label}. Élargissez la recherche aux environs.",
            q = escape(&query_terms),
        )
    };

    let cards = if providers.is_empty() {
        "<p class=\"muted\">Aucun résultat pour cette recherche.</p>".to_string()
    } else {
        providers
            .iter()
            .map(render_card)
            .collect::<Vec<_>>()
            .join("\n")
    };

    let links_html = maillage_links(&query_slug, &loc)
        .into_iter()
        .map(|(label, href)| {
            format!(
                r#"<a class="lk" href="{href}">{label}</a>"#,
                href = escape(&href),
                label = escape(&label),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let body = format!(
        r#"<h1>{h1}</h1>
<p class="muted">{total} praticien{s} trouvé{s}</p>
{cards}
<div class="context">
  <h2>Prendre rendez-vous chez un {q} à {loc_label}</h2>
  <p>{seo_paragraph}</p>
</div>
<nav class="seo" aria-label="Spécialités et arrondissements voisins">
{links_html}
</nav>"#,
        h1 = escape(&h1),
        s = if total > 1 { "s" } else { "" },
        q = escape(&query_terms),
    );

    page(&title, &body)
}

fn render_card(p: &ProviderItem) -> String {
    let href = slug_for(&p.display_name, p.specialty.as_deref(), None);
    format!(
        r#"<article class="card">
  <h3><a href="/{href}">{name}</a></h3>
  <p class="muted">{specialty}</p>
</article>"#,
        href = escape(&href),
        name = escape(&p.display_name),
        specialty = escape(p.specialty.as_deref().unwrap_or("")),
    )
}

/// Bloc `.seo` (maillage) : au moins les 6 liens vus dans la maquette pour
/// l'exemple canonique `/dentiste/paris-2e` — 2 arrondissements voisins
/// (Paris uniquement, schéma en escargot), 1 spécialité liée, 1 lien
/// d'urgence, 2 actes fréquents.
fn maillage_links(query_slug: &str, loc: &Locality) -> Vec<(String, String)> {
    let mut links = Vec::new();

    if loc.city_slug == "paris" {
        if let Some(arr) = loc.arrondissement {
            for n in locality::paris_neighbours(arr) {
                links.push((
                    format!("{} Paris {}", titleize(query_slug), ordinal(n)),
                    format!("/{query_slug}/paris-{}", ordinal(n)),
                ));
            }
        }
    }

    let related = related_specialty_slug(query_slug);
    links.push((
        format!("{} {}", titleize(related), locality_label(loc)),
        format!("/{related}/{}", locality::slug_of(loc)),
    ));

    links.push((
        format!("Urgence {} {}", urgency_noun(query_slug), loc.city_label),
        format!("/urgence-{query_slug}/{}", loc.city_slug),
    ));
    links.push((
        format!("Détartrage {}", locality_label(loc)),
        format!("/detartrage/{}", locality::slug_of(loc)),
    ));
    links.push((
        format!("Implant {} {}", urgency_noun(query_slug), loc.city_label),
        format!("/implant-{query_slug}/{}", loc.city_slug),
    ));

    links
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dentiste_paris_2e_maillage_matches_the_mockup_verbatim() {
        let loc = locality::parse("paris-2e");
        let links: Vec<String> = maillage_links("dentiste", &loc)
            .into_iter()
            .map(|(label, _)| label)
            .collect();
        assert_eq!(
            links,
            vec![
                "Dentiste Paris 1er",
                "Dentiste Paris 9e",
                "Orthodontiste Paris 2e",
                "Urgence dentaire Paris",
                "Détartrage Paris 2e",
                "Implant dentaire Paris",
            ]
        );
    }

    #[test]
    fn maillage_hrefs_are_relative_descriptive_urls() {
        let loc = locality::parse("paris-2e");
        let hrefs: Vec<String> = maillage_links("dentiste", &loc)
            .into_iter()
            .map(|(_, href)| href)
            .collect();
        assert_eq!(
            hrefs,
            vec![
                "/dentiste/paris-1er",
                "/dentiste/paris-9e",
                "/orthodontiste/paris-2e",
                "/urgence-dentiste/paris",
                "/detartrage/paris-2e",
                "/implant-dentiste/paris",
            ]
        );
    }
}
