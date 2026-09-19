//! `GET /:query_slug/:locality_slug` (ex. `/dentiste/paris-2e`) — page de
//! recherche SSR du tunnel web (#5356). Consomme
//! `marketplace::search_providers`, la MÊME fonction que l'API publique
//! `GET /v1/search/providers` — aucune requête ni logique dupliquée (#5355).

use std::collections::HashMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Redirect, Response};
use axum::Json;
use chrono::{DateTime, Datelike, Duration, Timelike, Utc};
use uuid::Uuid;

use crate::marketplace::{
    is_known_place, search_providers, search_slots, ProviderItem, SearchProvidersQuery, SlotRef,
};
use crate::AppState;

use super::html::{escape, page, PageMeta};
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

/// Rayon (km) appliqué autour du centre d'un arrondissement quand la page
/// cible en cite un (#7049) — volontairement serré (par contraste avec les
/// 20 km de `GEO_DEFAULT_RADIUS_KM` pour une recherche ville) : une page
/// d'arrondissement doit filtrer réellement, pas ré-élargir à tout Paris.
const ARRONDISSEMENT_RADIUS_KM: f64 = 1.0;

/// `near`/`place`/`radius_km` à passer à `search_providers` pour une
/// localité donnée (#7049). Une page d'arrondissement (`paris-13e`)
/// filtrait jusque-là par `place=paris` (rayon ville, 20 km) — l'arrondissement
/// parsé n'atteignait jamais la requête, si bien que les 20 pages
/// d'arrondissement d'une spécialité renvoyaient toutes la même liste que la
/// page ville. Quand le centre de l'arrondissement est connu, on filtre par
/// proximité à CE centre (rayon serré) plutôt que par la ville entière.
fn geo_params_for(loc: &Locality) -> (Option<String>, Option<String>, Option<f64>) {
    match loc
        .arrondissement
        .and_then(locality::paris_arrondissement_center)
    {
        Some((lat, lng)) => (
            Some(format!("{lat},{lng}")),
            None,
            Some(ARRONDISSEMENT_RADIUS_KM),
        ),
        None => (None, Some(loc.city_slug.clone()), None),
    }
}

/// Spécialités de premier niveau connues du tunnel — même liste que
/// `sitemap::TOP_LEVEL_SPECIALTIES` (module sœur), volontairement dupliquée
/// plutôt qu'exportée (même style que `sitemap::KNOWN_LOCALITIES`) : ce sont
/// TOUJOURS des slugs bruts, jamais un composé `urgence-`/`implant-` (#7295).
const KNOWN_SPECIALTIES: &[&str] = &["dentiste", "orthodontiste"];

/// Vrai si `specialty_slug` est une spécialité de premier niveau connue
/// (#7295) — condition nécessaire pour dériver un lien `urgence-`/`implant-`
/// ou pour qu'un `query_slug` de cette forme soit valide.
fn is_known_specialty_slug(specialty_slug: &str) -> bool {
    KNOWN_SPECIALTIES.contains(&specialty_slug)
}

/// #7295 — symétrique de `marketplace::is_known_place` (#7224) côté
/// `query_slug` : la route `/:query_slug/:locality_slug` a DEUX paramètres et
/// seul le second était validé. Un `query_slug` qui n'est ni une spécialité
/// connue, ni `detartrage`, ni `urgence-`/`implant-<spécialité connue>` n'a
/// aucun contenu propre à classer — un slug inventé (`pizza`) ou un slug déjà
/// préfixé (`implant-dentiste`) rendait quand même `200`/`index, follow` sous
/// un titre fabriqué par `page_subject_label`, et le maillage
/// (`maillage_links`) re-préfixait indéfiniment ce slug à chaque hop,
/// amorçant un espace d'URL infini depuis une page du sitemap.
fn is_known_query_slug(query_slug: &str) -> bool {
    if is_known_specialty_slug(query_slug) || query_slug == "detartrage" {
        return true;
    }
    if let Some(base) = query_slug
        .strip_prefix("urgence-")
        .or_else(|| query_slug.strip_prefix("implant-"))
    {
        return is_known_specialty_slug(base);
    }
    false
}

/// #7354 — root cause : `marketplace::resolve_place_coords` (donc
/// `is_known_place`) résout `locality_slug` en case-insensible
/// (`to_lowercase()`), mais `search_page` recopiait jusque-là la casse brute
/// de l'URL dans le `canonical` et le H1 (via `locality::parse`/`titleize`,
/// qui ne rabaissent pas une lettre déjà majuscule). Chaque variante de
/// casse d'une ville valide (`LYON`, `LyOn`, …) se déclarait donc canonique
/// sur elle-même — jusqu'à 2^len(ville) URL indexables pour une seule page
/// réelle. Une casse non normalisée doit rediriger en 301 vers le slug
/// normalisé plutôt que servir une énième page auto-canonique ; `Some(_)`
/// porte le chemin cible, `None` si `locality_slug` est déjà normalisé.
fn non_canonical_locality_redirect(query_slug: &str, locality_slug: &str) -> Option<String> {
    let normalized = locality_slug.to_lowercase();
    if normalized == locality_slug {
        return None;
    }
    Some(format!("/{query_slug}/{normalized}"))
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
) -> Response {
    if let Some(target) = non_canonical_locality_redirect(&query_slug, &locality_slug) {
        return Redirect::permanent(&target).into_response();
    }

    let loc = locality::parse(&locality_slug);

    // #7224 : un slug de ville hors du lookup géo statique
    // (`marketplace::KNOWN_CITY_COORDS`) désactivait le filtre géo au lieu de
    // faire échouer la page — la page rendait alors l'annuaire NATIONAL sous
    // un titre de ville fabriqué par `titleize()`, indexable et canonique.
    // Marseille/Bordeaux (villes connues sans praticien) doivent continuer à
    // servir l'état « Aucun résultat » ; seul un slug non reconnu 404.
    if !is_known_place(&loc.city_slug) {
        return locality_not_found(&query_slug, &locality_slug);
    }

    // #7295 : symétrique du garde-fou ville ci-dessus, côté second paramètre
    // de la route — voir `is_known_query_slug`.
    if !is_known_query_slug(&query_slug) {
        return query_not_found(&query_slug, &locality_slug);
    }

    let loc_label = locality_label(&loc);
    let query_terms = query_slug.replace('-', " ");

    let (near, place, radius_km) = geo_params_for(&loc);

    let params = SearchProvidersQuery {
        q: Some(query_terms.clone()),
        specialty: None,
        near,
        place,
        radius_km,
        bbox: None,
        sector: None,
        teleconsult: None,
        pmr: None,
        languages: None,
        accepts_new: None,
        accepts_new_patients: None,
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

    let mut meta = PageMeta::new(seo_paragraph, format!("/{query_slug}/{locality_slug}"));
    if !providers.is_empty() {
        meta = meta.json_ld(item_list_json_ld(&providers));
    }

    page(&title, &meta, &body).into_response()
}

/// `404` + `noindex` (#7224) : un slug de ville hors du lookup géo statique
/// n'a aucun contenu propre à classer — servir l'annuaire national sous un
/// titre de ville fabriqué produisait des pages satellites indexables au
/// contenu dupliqué (données fausses en prime). Même pattern que
/// `provider_page::not_found`.
fn locality_not_found(query_slug: &str, locality_slug: &str) -> Response {
    let body = r#"<h1>Ville introuvable</h1>
<div class="context">
  <p>Cette ville n'est pas référencée dans l'annuaire Nubia.</p>
</div>"#;
    let meta = PageMeta::new(
        "Cette ville n'est pas référencée dans l'annuaire Nubia.",
        format!("/{query_slug}/{locality_slug}"),
    )
    .robots("noindex");
    (
        StatusCode::NOT_FOUND,
        page("Ville introuvable — Nubia", &meta, body),
    )
        .into_response()
}

/// `404` + `noindex` (#7295) — symétrique de `locality_not_found` (#7224)
/// côté `query_slug` : un slug de spécialité/acte inventé ou déjà préfixé
/// n'a aucun contenu propre à classer — même justification mot pour mot que
/// #7224 : servir une page sous un titre fabriqué produisait des pages
/// satellites indexables au contenu dupliqué.
fn query_not_found(query_slug: &str, locality_slug: &str) -> Response {
    let body = r#"<h1>Recherche introuvable</h1>
<div class="context">
  <p>Cette spécialité ou cet acte n'est pas référencé dans l'annuaire Nubia.</p>
</div>"#;
    let meta = PageMeta::new(
        "Cette spécialité ou cet acte n'est pas référencé dans l'annuaire Nubia.",
        format!("/{query_slug}/{locality_slug}"),
    )
    .robots("noindex");
    (
        StatusCode::NOT_FOUND,
        page("Recherche introuvable — Nubia", &meta, body),
    )
        .into_response()
}

/// `ItemList` schema.org des praticiens de la page (#6720) — c'est le
/// signal de données structurées que la page de recherche peut réellement
/// justifier sans requête supplémentaire : chaque entrée est déjà connue
/// (`ProviderItem`), le lien pointe vers la fiche praticien réelle.
fn item_list_json_ld(providers: &[ProviderItem]) -> String {
    let base = super::html::tunnel_base_url();
    let items: Vec<serde_json::Value> = providers
        .iter()
        .enumerate()
        .map(|(idx, p)| {
            let href = slug_for(&p.display_name, p.specialty.as_deref(), None);
            serde_json::json!({
                "@type": "ListItem",
                "position": idx + 1,
                "url": format!("{base}/{href}"),
                "item": {
                    "@type": "Physician",
                    "name": p.display_name,
                    "medicalSpecialty": p.specialty,
                }
            })
        })
        .collect();

    serde_json::json!({
        "@context": "https://schema.org",
        "@type": "ItemList",
        "itemListElement": items,
    })
    .to_string()
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
/// `pub(super)` : réutilisé par `confirm_page` pour rappeler le jour du
/// créneau choisi dans le récapitulatif (#7073).
pub(super) fn day_label(dt: &DateTime<Utc>) -> String {
    let weekday = WEEKDAYS[dt.weekday().num_days_from_monday() as usize];
    format!("{weekday}. {} {}", dt.day(), MONTHS[dt.month0() as usize])
}

/// Même format que `_hhmm` (`modify_rdv_page.dart`). `pub(super)` : réutilisé
/// par `confirm_page` (#7073), même raison que [`day_label`].
pub(super) fn hhmm(dt: &DateTime<Utc>) -> String {
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
                        r#"<a class="chip" href="/reservation/confirmer?providerId={provider_id}&amp;slotId={slot_id}">{hhmm}</a>"#,
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

    // #7295 : un lien `urgence-`/`implant-` ne se fabrique QUE depuis une
    // spécialité de premier niveau connue (`is_known_specialty_slug`) — le
    // dériver d'un slug déjà préfixé (`implant-dentiste`) ou inventé
    // (`pizza`) re-préfixait indéfiniment à chaque hop
    // (`implant-implant-dentiste`, …), un espace d'URL infini amorcé en 2
    // clics depuis une page du sitemap.
    let can_derive_urgence_implant = is_known_specialty_slug(query_slug);

    if can_derive_urgence_implant {
        links.push((
            format!("Urgence {} {}", urgency_noun(query_slug), loc.city_label),
            format!("/urgence-{query_slug}/{}", loc.city_slug),
        ));
    }
    links.push((
        format!("Détartrage {}", locality_label(loc)),
        format!("/detartrage/{}", locality::slug_of(loc)),
    ));
    if can_derive_urgence_implant {
        links.push((
            format!("Implant {} {}", urgency_noun(query_slug), loc.city_label),
            format!("/implant-{query_slug}/{}", loc.city_slug),
        ));
    }

    links
}

#[cfg(test)]
mod tests {
    use super::*;

    /// #7354 — repro exacte de l'issue : `/dentiste/LYON` et `/dentiste/LyOn`
    /// doivent tous deux rediriger vers le slug de ville normalisé, pas se
    /// canoniser chacun sur eux-mêmes.
    #[test]
    fn non_canonical_locality_redirect_normalizes_any_case_variant() {
        assert_eq!(
            non_canonical_locality_redirect("dentiste", "LYON"),
            Some("/dentiste/lyon".to_string())
        );
        assert_eq!(
            non_canonical_locality_redirect("dentiste", "LyOn"),
            Some("/dentiste/lyon".to_string())
        );
    }

    #[test]
    fn non_canonical_locality_redirect_leaves_already_lowercase_slugs_alone() {
        assert_eq!(non_canonical_locality_redirect("dentiste", "lyon"), None);
        assert_eq!(
            non_canonical_locality_redirect("dentiste", "paris-2e"),
            None
        );
    }

    #[test]
    fn page_subject_label_keeps_specialty_pluralization_unchanged() {
        assert_eq!(page_subject_label("dentiste"), "Chirurgiens-dentistes");
        assert_eq!(page_subject_label("orthodontiste"), "Orthodontistes");
    }

    /// #7049 : `/dentiste/paris` (pas d'arrondissement) doit continuer à
    /// filtrer par ville (rayon 20 km, `place`), comportement inchangé.
    #[test]
    fn geo_params_for_city_only_locality_uses_place() {
        let loc = locality::parse("paris");
        assert_eq!(
            geo_params_for(&loc),
            (None, Some("paris".to_string()), None)
        );
    }

    /// #7049 — root cause : `paris-13e` filtrait jusque-là par `place=paris`
    /// (même rayon ville que `/dentiste/paris`), l'arrondissement parsé
    /// n'atteignait jamais la requête. Doit désormais filtrer par proximité
    /// au centre du 13e, avec un rayon serré, PAS par ville.
    #[test]
    fn geo_params_for_arrondissement_locality_uses_a_tight_near_radius() {
        let loc = locality::parse("paris-13e");
        let (near, place, radius_km) = geo_params_for(&loc);
        assert_eq!(place, None);
        assert_eq!(radius_km, Some(ARRONDISSEMENT_RADIUS_KM));
        assert!(
            radius_km.unwrap() < 20.0,
            "doit être plus serré que le rayon ville"
        );
        let near = near.expect("un arrondissement connu doit résoudre des coordonnées");
        let mut parts = near.splitn(2, ',');
        let lat: f64 = parts.next().unwrap().parse().unwrap();
        let lng: f64 = parts.next().unwrap().parse().unwrap();
        assert_eq!(
            (lat, lng),
            locality::paris_arrondissement_center(13).unwrap()
        );
    }

    /// Deux arrondissements distincts doivent résoudre des centres distincts
    /// — sinon la requête resterait identique d'une page à l'autre malgré
    /// le rayon serré (#7049).
    #[test]
    fn geo_params_for_distinct_arrondissements_resolve_distinct_centers() {
        let loc_1er = locality::parse("paris-1er");
        let loc_20e = locality::parse("paris-20e");
        assert_ne!(geo_params_for(&loc_1er).0, geo_params_for(&loc_20e).0);
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

    /// #7224 — root cause : un slug de ville inventé (`asdfgh-qwerty`,
    /// `new-york`, …) désactivait le filtre géo au lieu de faire échouer la
    /// page, servant l'annuaire national sous un titre de ville fabriqué,
    /// indexable et canonique. `locality_not_found` doit poser `404` +
    /// `noindex`, comme `provider_page::not_found` pour une fiche inconnue.
    #[tokio::test]
    async fn locality_not_found_is_a_404_page_with_noindex() {
        let response = locality_not_found("dentiste", "asdfgh-qwerty");
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let html = String::from_utf8(body.to_vec()).unwrap();
        assert!(html.contains(r#"<meta name="robots" content="noindex">"#));
        assert!(html.contains("<h1>Ville introuvable</h1>"));
    }

    /// #7295 — root cause : `#7224` n'a validé que la ville. Un slug de
    /// spécialité/acte inventé (`pizza`) ou déjà préfixé (`implant-dentiste`
    /// re-préfixé en `implant-implant-dentiste`) doit être rejeté au même
    /// titre que les vrais slugs connus doivent rester acceptés.
    #[test]
    fn is_known_query_slug_accepts_only_known_specialties_and_actes() {
        assert!(is_known_query_slug("dentiste"));
        assert!(is_known_query_slug("orthodontiste"));
        assert!(is_known_query_slug("detartrage"));
        assert!(is_known_query_slug("urgence-dentiste"));
        assert!(is_known_query_slug("implant-orthodontiste"));

        assert!(!is_known_query_slug("pizza"));
        assert!(!is_known_query_slug("urgence-pizza"));
        assert!(!is_known_query_slug("implant-pizza"));
        assert!(!is_known_query_slug("implant-dentiste-invalide"));
        // Slug déjà préfixé re-préfixé : le vecteur de récursion infinie.
        assert!(!is_known_query_slug("implant-implant-dentiste"));
        assert!(!is_known_query_slug("urgence-implant-dentiste"));
        assert!(!is_known_query_slug("implant-urgence-dentiste"));
    }

    /// #7295 : même traitement 404+noindex que `locality_not_found` (#7224),
    /// côté `query_slug` cette fois.
    #[tokio::test]
    async fn query_not_found_is_a_404_page_with_noindex() {
        let response = query_not_found("pizza", "paris");
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        let body = axum::body::to_bytes(response.into_body(), usize::MAX)
            .await
            .unwrap();
        let html = String::from_utf8(body.to_vec()).unwrap();
        assert!(html.contains(r#"<meta name="robots" content="noindex">"#));
        assert!(html.contains("<h1>Recherche introuvable</h1>"));
    }

    /// #7295 — root cause de la récursion infinie : `maillage_links` re-
    /// préfixait n'importe quel `query_slug` reçu, y compris un slug déjà
    /// préfixé (`implant-dentiste`) ou inventé (`pizza`). Seule une
    /// spécialité brute connue (`dentiste`, `orthodontiste`) doit produire un
    /// lien `urgence-`/`implant-`.
    #[test]
    fn maillage_links_never_derives_urgence_or_implant_from_a_prefixed_or_unknown_slug() {
        let loc = locality::parse("paris");
        for query_slug in [
            "implant-dentiste",
            "urgence-dentiste",
            "pizza",
            "detartrage",
        ] {
            let hrefs: Vec<String> = maillage_links(query_slug, &loc)
                .into_iter()
                .map(|(_, href)| href)
                .collect();
            assert!(
                hrefs
                    .iter()
                    .all(|h| !h.starts_with("/urgence-") && !h.starts_with("/implant-")),
                "query_slug={query_slug:?} a produit un lien urgence-/implant- : {hrefs:?}"
            );
        }
    }
}
