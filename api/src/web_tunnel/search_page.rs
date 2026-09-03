//! `GET /:query_slug/:locality_slug` (ex. `/dentiste/paris-2e`) — page de
//! recherche SSR du tunnel web (#5356). Consomme
//! `marketplace::search_providers`, la MÊME fonction que l'API publique
//! `GET /v1/search/providers` — aucune requête ni logique dupliquée (#5355).

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::response::IntoResponse;
use axum::Json;
use chrono::{DateTime, Datelike, Duration, Timelike, Utc};
use uuid::Uuid;

use crate::marketplace::{
    search_providers, search_slots, ProviderItem, SearchProvidersQuery, SlotRef,
};
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

/// Libellé du sujet de page (H1/`<title>`) pour un `query_slug` arrivant sur
/// `/:query_slug/:locality_slug` — cette route sert aussi bien les pages de
/// spécialité (`dentiste`, pluriel) que les pages d'acte générées par
/// [`maillage_links`] (`detartrage`, `urgence-<spécialité>`,
/// `implant-<spécialité>`), toutes deux visitables depuis les liens `.seo`.
/// `specialty_plural_label` seule les traitait comme des spécialités : slug
/// sans accent passé tel quel à `titleize` (« Detartrages », accent perdu) ET
/// pluralisé comme un métier alors qu'un acte ne se pluralise pas (#6318).
/// Les préfixes `urgence-`/`implant-` réutilisent volontairement
/// [`urgency_noun`], la même logique que celle qui a produit le libellé du
/// lien menant ici (cohérence lien → H1).
fn page_subject_label(query_slug: &str) -> String {
    if let Some(base) = query_slug.strip_prefix("urgence-") {
        return format!("Urgence {}", urgency_noun(base));
    }
    if let Some(base) = query_slug.strip_prefix("implant-") {
        return format!("Implant {}", urgency_noun(base));
    }
    match query_slug {
        "detartrage" => "Détartrage".to_string(),
        _ => specialty_plural_label(query_slug),
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

    let (providers, total) =
        match search_providers(State(state.clone()), Query(params.clone())).await {
            Ok(Json(resp)) => (resp.data, resp.page.total),
            Err(_) => (Vec::new(), 0),
        };

    // Grille « 3 jours de créneaux » (#6318) : `search_slots`, MÊME fonction
    // que l'API publique `/v1/search/slots`, réinterrogée avec les mêmes
    // filtres que `search_providers` ci-dessus — aucune requête ni logique
    // dupliquée (#5355), comme le reste de ce module.
    let slots_by_provider: HashMap<Uuid, Vec<SlotRef>> =
        match search_slots(State(state), Query(params)).await {
            Ok(Json(resp)) => resp
                .data
                .into_iter()
                .map(|item| (item.provider_id, item.slots))
                .collect(),
            Err(_) => HashMap::new(),
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

    let h1 = format!("{} à {}", page_subject_label(&query_slug), loc_label);
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

    let empty_slots: Vec<SlotRef> = Vec::new();
    let cards = if providers.is_empty() {
        "<p class=\"muted\">Aucun résultat pour cette recherche.</p>".to_string()
    } else {
        providers
            .iter()
            .map(|p| {
                render_card(
                    p,
                    slots_by_provider
                        .get(&p.provider_id)
                        .unwrap_or(&empty_slots),
                )
            })
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

fn render_card(p: &ProviderItem, slots: &[SlotRef]) -> String {
    let href = slug_for(&p.display_name, p.specialty.as_deref(), None);
    format!(
        r#"<article class="card">
  <h3><a href="/{href}">{name}</a></h3>
  <p class="muted">{specialty}</p>
  {tags}
  {slots_block}
</article>"#,
        href = escape(&href),
        name = escape(&p.display_name),
        specialty = escape(p.specialty.as_deref().unwrap_or("")),
        tags = render_tags(p),
        slots_block = render_slots_block(p.provider_id, slots, &href),
    )
}

/// Attributs patient de la maquette (secteur, tiers payant, nouveaux
/// patients, PMR) — déjà remontés par `search_providers` (#5359) mais
/// jusqu'ici jamais rendus sur la carte (#6318).
fn render_tags(p: &ProviderItem) -> String {
    let mut tags = Vec::new();
    if let Some(sector) = p.sector.as_deref() {
        tags.push(format!("Secteur {sector}"));
    }
    if p.tiers_payant == Some(true) {
        tags.push("Tiers payant".to_string());
    }
    if p.accepts_new_patients == Some(true) {
        tags.push("Nouveaux patients".to_string());
    }
    if p.pmr == Some(true) {
        tags.push("Accès PMR".to_string());
    }
    if tags.is_empty() {
        return String::new();
    }
    format!(
        r#"<p class="tags">{}</p>"#,
        tags.iter()
            .map(|t| format!(r#"<span class="tag">{}</span>"#, escape(t)))
            .collect::<Vec<_>>()
            .join(" ")
    )
}

/// Nombre de jours affichés dans la grille de chaque carte — « trois jours
/// de créneaux réels par résultat » (maquette, note 1).
const GRID_DAYS: usize = 3;
/// Nombre de créneaux affichés par jour avant de renvoyer vers le lien de
/// débord « Voir plus de créneaux ».
const GRID_SLOTS_PER_DAY: usize = 4;

const WEEKDAYS: [&str; 7] = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"];
const MONTHS: [&str; 12] = [
    "jan", "fév", "mar", "avr", "mai", "jun", "jul", "aoû", "sep", "oct", "nov", "déc",
];

/// Même format que `_dayHeader` (`modify_rdv_page.dart`), vocabulaire des
/// créneaux explicitement partagé avec l'app (maquette, encadré « Le
/// vocabulaire des créneaux est déjà celui de l'app »).
fn day_label(dt: &DateTime<Utc>) -> String {
    let weekday = WEEKDAYS[dt.weekday().num_days_from_monday() as usize];
    format!("{weekday}. {} {}", dt.day(), MONTHS[dt.month0() as usize])
}

/// Même format que `_hhmm` (`modify_rdv_page.dart`).
fn hhmm(dt: &DateTime<Utc>) -> String {
    format!("{:02}:{:02}", dt.hour(), dt.minute())
}

/// `pub(super)` : réutilisé par `provider_page` pour l'agenda de la fiche
/// praticien (#6318) — même groupement par jour, pas de logique dupliquée.
pub(super) struct DayGroup {
    pub(super) label: String,
    pub(super) slots: Vec<(String, Uuid)>,
}

/// Groupe les créneaux (déjà triés par `starts_at` ASC côté SQL) par jour
/// calendaire, comme `_SlotsByDay` (`modify_rdv_page.dart`).
pub(super) fn group_slots_by_day(slots: &[SlotRef]) -> Vec<DayGroup> {
    let mut groups: Vec<DayGroup> = Vec::new();
    for slot in slots {
        let Some(dt) = DateTime::parse_from_rfc3339(&slot.starts_at)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
        else {
            continue;
        };
        let label = day_label(&dt);
        match groups.last_mut() {
            Some(g) if g.label == label => g.slots.push((hhmm(&dt), slot.slot_id)),
            _ => groups.push(DayGroup {
                label,
                slots: vec![(hhmm(&dt), slot.slot_id)],
            }),
        }
    }
    groups
}

/// Grille « 3 jours de créneaux » cliquables de la carte praticien, ou repli
/// « aucun créneau en ligne » (maquette, 3e résultat) quand le praticien
/// n'a aucune disponibilité — ce n'est pas un état d'erreur, une carte reste
/// une réponse utile même sans agenda connecté (#6318).
fn render_slots_block(provider_id: Uuid, slots: &[SlotRef], provider_href: &str) -> String {
    if slots.is_empty() {
        return format!(
            r#"<div class="nosl">
    <p class="muted">Aucun créneau en ligne pour ce praticien</p>
    <a href="/{href}">Voir sa fiche et ses coordonnées</a>
  </div>"#,
            href = escape(provider_href),
        );
    }

    let days = group_slots_by_day(slots);
    let shown_days = &days[..days.len().min(GRID_DAYS)];
    let has_more = days.len() > GRID_DAYS
        || shown_days
            .iter()
            .any(|d| d.slots.len() > GRID_SLOTS_PER_DAY);

    let days_html = shown_days
        .iter()
        .map(|day| {
            let chips = day
                .slots
                .iter()
                .take(GRID_SLOTS_PER_DAY)
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

    let more = if has_more {
        format!(
            r#"<a class="more" href="/{href}">Voir plus de créneaux</a>"#,
            href = escape(provider_href),
        )
    } else {
        String::new()
    };

    format!(r#"<div class="slots">{days_html}{more}</div>"#)
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
    fn page_subject_label_keeps_specialty_pluralization_unchanged() {
        assert_eq!(page_subject_label("dentiste"), "Chirurgiens-dentistes");
        assert_eq!(page_subject_label("orthodontiste"), "Orthodontistes");
    }

    /// #6318 : les pages d'acte atteintes depuis `maillage_links` perdaient
    /// leurs accents (slugifiées) et se voyaient pluralisées comme un métier
    /// (« Detartrages », « Urgence Dentistes ») — un acte ne se pluralise pas.
    #[test]
    fn page_subject_label_restores_accents_and_does_not_pluralize_actes() {
        assert_eq!(page_subject_label("detartrage"), "Détartrage");
        assert_eq!(page_subject_label("urgence-dentiste"), "Urgence dentaire");
        assert_eq!(page_subject_label("implant-dentiste"), "Implant dentaire");
        assert_eq!(
            page_subject_label("urgence-orthodontiste"),
            "Urgence médicale"
        );
    }

    #[test]
    fn group_slots_by_day_groups_consecutive_same_day_slots() {
        let slots = vec![
            SlotRef {
                slot_id: Uuid::nil(),
                starts_at: "2026-08-11T14:30:00Z".to_string(),
            },
            SlotRef {
                slot_id: Uuid::nil(),
                starts_at: "2026-08-11T15:00:00Z".to_string(),
            },
            SlotRef {
                slot_id: Uuid::nil(),
                starts_at: "2026-08-12T09:00:00Z".to_string(),
            },
        ];
        let days = group_slots_by_day(&slots);
        assert_eq!(days.len(), 2);
        // "aoû" (pas "août") : même abréviation que `_months` dans
        // `modify_rdv_page.dart`, reprise telle quelle (#6318).
        assert_eq!(days[0].label, "Mar. 11 aoû");
        assert_eq!(
            days[0]
                .slots
                .iter()
                .map(|(t, _)| t.as_str())
                .collect::<Vec<_>>(),
            vec!["14:30", "15:00"]
        );
        assert_eq!(days[1].label, "Mer. 12 aoû");
        assert_eq!(days[1].slots.len(), 1);
    }

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
