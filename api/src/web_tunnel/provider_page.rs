//! `GET /:slug` (ex. `/dr-amelie-rousseau-dentiste-paris`) — fiche
//! praticien SSR (#5356). Résout le slug en `provider_id` par préfixe de nom
//! (le nom du praticien est toujours le préfixe du slug produit par
//! [`slug_for`], utilisé aussi bien ici que par les cartes de la page de
//! recherche) puis appelle `marketplace::get_provider`, la MÊME fonction que
//! l'API publique `GET /v1/providers/:id` — aucune logique dupliquée
//! (#5355).

use std::collections::BTreeMap;

use axum::extract::{Path, Query, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use chrono::{DateTime, Datelike, Duration, NaiveDate, Utc};
use serde::Deserialize;
use uuid::Uuid;

use crate::marketplace::{
    get_provider, search_providers, search_slots, ProviderProfile, SearchProvidersQuery, SlotRef,
};
use crate::AppState;

use super::html::{escape, page, tunnel_base_url, PageMeta};
use super::search_page::{day_label, hhmm, MONTHS, WEEKDAYS};
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

/// `?semaine=` (#6791) : index 0-based de semaine affichée dans la grille de
/// l'agenda — paramètre de requête plutôt que de chemin, comme les facettes
/// de `search_page` (le canonical ignore volontairement cette pagination,
/// même convention).
#[derive(Deserialize)]
pub struct ProviderPageQuery {
    semaine: Option<i64>,
}

pub async fn provider_page(
    State(state): State<AppState>,
    Path(slug): Path<String>,
    Query(page_query): Query<ProviderPageQuery>,
) -> Response {
    let Some(term) = search_term_from_slug(&slug) else {
        return not_found(&slug);
    };

    let params = SearchProvidersQuery {
        q: Some(term.to_string()),
        specialty: None,
        specialty_id: None,
        near: None,
        lat: None,
        lng: None,
        place: None,
        radius_km: None,
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
        from: None,
        to: None,
    };

    let candidates = match search_providers(State(state.clone()), Query(params)).await {
        Ok(Json(resp)) => resp.data,
        Err(_) => Vec::new(),
    };

    let Some(matched) = candidates
        .into_iter()
        .find(|p| slug.starts_with(&slugify(&p.display_name)))
    else {
        return not_found(&slug);
    };

    let profile = match get_provider(State(state.clone()), Path(matched.provider_id)).await {
        Ok(Json(profile)) => profile,
        Err(_) => return not_found(&slug),
    };

    // Agenda de la fiche (#6318) : `search_slots`, MÊME fonction que l'API
    // publique `/v1/search/slots`, restreinte à ce praticien via
    // `provider_id` — aucune requête de créneaux dupliquée (#5355). Cette
    // page EST la destination du lien de débord de la carte de recherche,
    // donc TOUS les créneaux ouverts sont récupérés ici (pas de `from`/`to`),
    // sans grille tronquée — [`render_agenda_week`] les pagine ensuite par
    // semaine (#6791 : l'ancien rendu les déversait tous dans un seul bloc).
    let slots_params = SearchProvidersQuery {
        q: None,
        specialty: None,
        specialty_id: None,
        near: None,
        lat: None,
        lng: None,
        place: None,
        radius_km: None,
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
        per_page: Some(1),
        provider_id: Some(matched.provider_id.to_string()),
        date: None,
        from: None,
        to: None,
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

    let badges = render_badges(&profile);
    let next_availability = render_next_availability(matched.provider_id, slots.first());
    let agenda = render_agenda_week(matched.provider_id, &slots, page_query.semaine.unwrap_or(0));
    let access = render_access_section(&profile);

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

    let context = render_context(&profile, &h1, city);

    let title = format!("{h1} — Nubia");
    let body = format!(
        r#"<h1>{h1}</h1>
<p class="muted">{subtitle}</p>
{badges}
{next_availability}
<div class="context">
  <h2>Présentation</h2>
  <p>{context}</p>
</div>
{agenda}
{access}
<p><a href="/reservation/confirmer?providerId={provider_id}">Prendre rendez-vous</a></p>"#,
        h1 = escape(&h1),
        subtitle = escape(&subtitle),
        provider_id = profile.provider_id,
    );

    // Canonical = le MÊME slug que celui produit pour la carte de résultat
    // (`render_card`, `search_page.rs`) : plusieurs variantes de slug
    // résolvent ici par préfixe (cf. doc du handler) — sans un canonical
    // pointant vers une URL unique, chaque variante serait un doublon
    // structurel (#6720).
    let canonical_path = format!(
        "/{}",
        slug_for(&profile.display_name, profile.specialty.as_deref(), None)
    );
    let canonical_url = format!("{}{canonical_path}", tunnel_base_url());
    let meta = PageMeta::new(provider_description(&profile, &h1, city), canonical_path)
        .og_type("profile")
        .json_ld(provider_json_ld(&profile, &canonical_url, city));

    page(&title, &meta, &body).into_response()
}

/// Texte brut (pas de HTML) du `<meta name="description">`/`og:description`
/// — même hiérarchie de repli que [`render_context`] (bio, sinon phrase
/// ville/secteur, sinon tautologie) mais sans échappement HTML : `page()`
/// échappe une seule fois pour l'attribut, échapper ici doublerait les
/// entités (`&` → `&amp;amp;`).
fn provider_description(profile: &ProviderProfile, h1: &str, city: &str) -> String {
    if let Some(bio) = profile
        .bio
        .as_deref()
        .map(str::trim)
        .filter(|b| !b.is_empty())
    {
        return bio.to_string();
    }
    if !city.is_empty() {
        return format!(
            "Prendre rendez-vous avec {h1}{sector} à {city} sur Nubia.",
            sector = profile
                .sector
                .as_deref()
                .map(|s| format!(", secteur {s}"))
                .unwrap_or_default(),
        );
    }
    format!("Prendre rendez-vous avec {h1} sur Nubia.")
}

/// JSON-LD `Physician` (schema.org) — le signal qui produit les résultats
/// enrichis (adresse, avis) d'un annuaire de santé local (#6720). N'inclut
/// que les champs réellement connus : pas de `null` inventé pour un champ
/// absent (adresse partielle, aucun avis publié).
fn provider_json_ld(profile: &ProviderProfile, canonical_url: &str, city: &str) -> String {
    let mut root = serde_json::Map::new();
    root.insert("@context".into(), serde_json::json!("https://schema.org"));
    root.insert("@type".into(), serde_json::json!("Physician"));
    root.insert("name".into(), serde_json::json!(profile.display_name));
    root.insert("url".into(), serde_json::json!(canonical_url));
    if let Some(specialty) = profile.specialty.as_deref() {
        root.insert("medicalSpecialty".into(), serde_json::json!(specialty));
    }

    if let Some(address) = profile.address.as_ref() {
        let mut addr = serde_json::Map::new();
        addr.insert("@type".into(), serde_json::json!("PostalAddress"));
        if let Some(street) = address.get("rue").and_then(|v| v.as_str()) {
            addr.insert("streetAddress".into(), serde_json::json!(street));
        }
        if let Some(postal) = address.get("cp").and_then(|v| v.as_str()) {
            addr.insert("postalCode".into(), serde_json::json!(postal));
        }
        if !city.is_empty() {
            addr.insert("addressLocality".into(), serde_json::json!(city));
        }
        addr.insert("addressCountry".into(), serde_json::json!("FR"));
        root.insert("address".into(), serde_json::Value::Object(addr));
    }

    if let Some(rating_avg) = profile.rating_avg.filter(|_| profile.review_count > 0) {
        root.insert(
            "aggregateRating".into(),
            serde_json::json!({
                "@type": "AggregateRating",
                "ratingValue": rating_avg,
                "reviewCount": profile.review_count,
            }),
        );
    }

    serde_json::Value::Object(root).to_string()
}

/// Paragraphe de présentation de la fiche praticien (#6721) : la `bio` quand
/// elle existe (texte le plus riche disponible), sinon repli sur "exerce à
/// {city}" quand une adresse est connue, sinon la tautologie minimale. Les
/// faits pratiques (secteur, tiers payant, PMR) ne sont plus fondus ici en
/// prose depuis #6791 — ils sont rendus en badges structurés par
/// [`render_badges`], comme la maquette.
fn render_context(profile: &ProviderProfile, h1: &str, city: &str) -> String {
    match profile.bio.as_deref().map(str::trim) {
        Some(bio) if !bio.is_empty() => escape(bio),
        _ if !city.is_empty() => format!(
            "{name} exerce{sector} à {city}.",
            name = escape(h1),
            sector = profile
                .sector
                .as_deref()
                .map(|s| format!(" en secteur {}", escape(s)))
                .unwrap_or_default(),
            city = escape(city),
        ),
        _ => format!("Profil du praticien {}.", escape(h1)),
    }
}

/// Ligne de badges (maquette, écran ② : « Secteur 1 — tarifs conventionnés »,
/// « Tiers payant », « Nouveaux patients acceptés », « Accès PMR », « Carte
/// bancaire ») — #6791, root cause du point 1 de l'audit : ces faits
/// n'étaient rendus que fondus dans la phrase de `render_context`, jamais
/// comme des badges distincts. « Carte bancaire » n'a aucune colonne
/// correspondante côté `provider`/`establishment` — omis plutôt qu'affiché
/// avec une valeur fabriquée (même règle que `seo_paragraph`/les facettes
/// omises de `search_page`, #7659).
fn render_badges(profile: &ProviderProfile) -> String {
    let mut badges = Vec::new();
    if let Some(sector) = profile.sector.as_deref() {
        badges.push(format!("Secteur {} — tarifs conventionnés", escape(sector)));
    }
    if profile.tiers_payant.unwrap_or(false) {
        badges.push("Tiers payant".to_string());
    }
    if profile.accepts_new_patients.unwrap_or(false) {
        badges.push("Nouveaux patients acceptés".to_string());
    }
    if profile.pmr.unwrap_or(false) {
        badges.push("Accès PMR".to_string());
    }

    if badges.is_empty() {
        return String::new();
    }
    let tags = badges
        .into_iter()
        .map(|b| format!(r#"<span class="tag">{b}</span>"#))
        .collect::<Vec<_>>()
        .join("");
    format!(r#"<div class="tags">{tags}</div>"#)
}

/// Bandeau « Prochaine disponibilité » (maquette, écran ②) — #6791, point 2
/// de l'audit. Dérivé du 1er créneau de `slots` (déjà trié `starts_at` ASC
/// côté SQL, cf. `search_slots`), pas d'une seconde requête : même créneau
/// que celui qui ouvre la grille de [`render_agenda_week`].
fn render_next_availability(provider_id: Uuid, next_slot: Option<&SlotRef>) -> String {
    let Some(slot) = next_slot else {
        return String::new();
    };
    let Some(dt) = DateTime::parse_from_rfc3339(&slot.starts_at)
        .ok()
        .map(|dt| dt.with_timezone(&Utc))
    else {
        return String::new();
    };

    let today = Utc::now().date_naive();
    let label = if dt.date_naive() == today {
        format!("Aujourd'hui, {}", hhmm(&dt))
    } else if dt.date_naive() == today + Duration::days(1) {
        format!("Demain, {}", hhmm(&dt))
    } else {
        format!("{}, {}", day_label(&dt), hhmm(&dt))
    };

    // `label` est entièrement composé de littéraux statiques et de nombres
    // (jour/mois/heure) — jamais de donnée utilisateur, pas d'échappement
    // nécessaire (échapper doublerait l'apostrophe de « Aujourd'hui » en
    // `&#39;`).
    format!(
        r#"<div class="nextav"><div><span class="lb">Prochaine disponibilité</span><br><span class="vv">{label}</span></div><a href="/reservation/confirmer?providerId={provider_id}&amp;slotId={slot_id}">Prendre rendez-vous</a></div>"#,
        slot_id = slot.slot_id,
    )
}

/// Lundi de la semaine calendaire (#6791) contenant `date`.
fn monday_of(date: NaiveDate) -> NaiveDate {
    date - Duration::days(date.weekday().num_days_from_monday() as i64)
}

/// « 11 – 16 août » (même mois) ou « 29 jul. – 3 août » (chevauchement de
/// mois) — en-tête de la grille semaine (#6791).
fn week_range_label(start: NaiveDate, end: NaiveDate) -> String {
    if start.month() == end.month() {
        format!(
            "{} – {} {}",
            start.day(),
            end.day(),
            MONTHS[start.month0() as usize]
        )
    } else {
        format!(
            "{} {} – {} {}",
            start.day(),
            MONTHS[start.month0() as usize],
            end.day(),
            MONTHS[end.month0() as usize],
        )
    }
}

/// Nombre de créneaux affichés par jour dans la grille semaine — même
/// gabarit que la maquette (« six lignes-jour de six créneaux »).
const CHIPS_PER_DAY: usize = 6;
/// Lundi à samedi — même étendue que la maquette (dimanche n'a pas de ligne
/// de créneaux, cf. bloc horaires « Dimanche Fermé »).
const WEEK_DAYS: i64 = 6;

/// Grille semaine paginée de l'agenda (maquette, écran ②, point 4 de
/// l'audit #6791) — root cause du bug « 165 puces en vrac » : la page
/// dumpait TOUS les jours à créneaux ouverts (`search_slots` ne borne pas
/// dans le temps) dans un seul bloc `.slots`, sans titre ni pagination.
/// Reste un repli explicite (pas un état vide silencieux) quand le
/// praticien n'a aucun créneau en ligne (#6318) — comportement inchangé
/// pour ce cas.
fn render_agenda_week(provider_id: Uuid, slots: &[SlotRef], semaine: i64) -> String {
    let mut per_day: BTreeMap<NaiveDate, Vec<(DateTime<Utc>, Uuid)>> = BTreeMap::new();
    for slot in slots {
        if let Some(dt) = DateTime::parse_from_rfc3339(&slot.starts_at)
            .ok()
            .map(|dt| dt.with_timezone(&Utc))
        {
            per_day
                .entry(dt.date_naive())
                .or_default()
                .push((dt, slot.slot_id));
        }
    }

    if per_day.is_empty() {
        return r#"<h2>Choisissez un créneau</h2>
<div class="nosl">
  <p class="muted">Aucun créneau en ligne pour ce praticien pour le moment.</p>
</div>"#
            .to_string();
    }

    let weeks = per_day
        .keys()
        .map(|date| monday_of(*date))
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let idx = (semaine.max(0) as usize).min(weeks.len() - 1);
    let week_start = weeks[idx];
    let week_end = week_start + Duration::days(WEEK_DAYS - 1);

    let prev = if idx > 0 {
        format!(
            r#"<a class="b" href="?semaine={}">chevron_left</a>"#,
            idx - 1
        )
    } else {
        r#"<span class="b off">chevron_left</span>"#.to_string()
    };
    let next = if idx + 1 < weeks.len() {
        format!(
            r#"<a class="b" href="?semaine={}">chevron_right</a>"#,
            idx + 1
        )
    } else {
        r#"<span class="b off">chevron_right</span>"#.to_string()
    };

    let days_html = (0..WEEK_DAYS)
        .map(|i| {
            let date = week_start + Duration::days(i);
            let label = format!("{}. {}", WEEKDAYS[i as usize], date.day());
            let mut chips = per_day
                .get(&date)
                .map(|day_slots| {
                    day_slots
                        .iter()
                        .take(CHIPS_PER_DAY)
                        .map(|(dt, slot_id)| {
                            format!(
                                r#"<a class="chip" href="/reservation/confirmer?providerId={provider_id}&amp;slotId={slot_id}">{hhmm}</a>"#,
                                hhmm = hhmm(dt),
                            )
                        })
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();
            while chips.len() < CHIPS_PER_DAY {
                chips.push(r#"<span class="chip off">—</span>"#.to_string());
            }
            format!(
                r#"<div class="day"><span class="dlabel">{label}</span>{chips}</div>"#,
                label = escape(&label),
                chips = chips.join(""),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        r#"<div class="agh"><h2>Choisissez un créneau</h2><div class="navw">{prev}<span>{title}</span>{next}</div></div>
<div class="slots">{days_html}</div>"#,
        title = escape(&week_range_label(week_start, week_end)),
    )
}

/// Bloc « Accès » (maquette, écran ②, point 5 de l'audit #6791) :
/// établissement + adresse quand connus. Métro/téléphone n'ont aucune
/// colonne côté `establishment`/`provider` — omis plutôt qu'inventés, même
/// règle que [`render_badges`]. `address` nul (cas réel pour ce praticien de
/// démo, cf. l'issue) rend un repli explicite plutôt qu'un bloc vide
/// silencieux, même convention que [`render_agenda_week`].
fn render_access_section(profile: &ProviderProfile) -> String {
    let mut rows = Vec::new();
    if let Some(name) = profile.establishment_name.as_deref() {
        rows.push(format!(
            r#"<div class="kv"><span class="k">Cabinet</span><span class="v">{}</span></div>"#,
            escape(name),
        ));
    }

    let address = profile.address.as_ref().and_then(|a| {
        let rue = a.get("rue").and_then(|v| v.as_str())?;
        let cp = a.get("cp").and_then(|v| v.as_str()).unwrap_or_default();
        let ville = a.get("ville").and_then(|v| v.as_str()).unwrap_or_default();
        Some(format!(
            "{}<br>{} {}",
            escape(rue),
            escape(cp),
            escape(ville)
        ))
    });
    rows.push(match address {
        Some(addr) => format!(
            r#"<div class="kv"><span class="k">Adresse</span><span class="v">{addr}</span></div>"#
        ),
        None => r#"<div class="kv"><span class="k">Adresse</span><span class="v muted">Non communiquée en ligne</span></div>"#
            .to_string(),
    });

    format!(
        r#"<div class="card3"><h2>Accès</h2>{}</div>"#,
        rows.join("")
    )
}

/// `noindex` (#6720) : une fiche introuvable n'a aucun contenu propre à
/// classer — le `404` HTTP suffit déjà à écarter la page, la balise évite en
/// plus qu'un moteur la garde indexée après un slug devenu invalide.
fn not_found(slug: &str) -> Response {
    let body = r#"<h1>Praticien introuvable</h1>
<div class="context">
  <p>Ce profil n'existe pas ou n'est plus référencé dans l'annuaire Nubia.</p>
</div>"#;
    let meta = PageMeta::new(
        "Ce profil n'existe pas ou n'est plus référencé dans l'annuaire Nubia.",
        format!("/{slug}"),
    )
    .robots("noindex");
    (
        StatusCode::NOT_FOUND,
        page("Praticien introuvable — Nubia", &meta, body),
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

    fn mk_profile() -> ProviderProfile {
        ProviderProfile {
            provider_id: Uuid::nil(),
            display_name: "Dr Amélie Dubois".to_string(),
            specialty: None,
            profession: None,
            sector: None,
            rpps_verified: true,
            is_listed: true,
            bio: None,
            languages: None,
            address: None,
            geo: None,
            tiers_payant: None,
            teleconsult: None,
            pmr: None,
            accepts_new_patients: None,
            establishment_id: None,
            establishment_name: None,
            rating_avg: None,
            review_count: 0,
        }
    }

    fn slot_at(rfc3339: &str) -> SlotRef {
        SlotRef {
            slot_id: Uuid::nil(),
            starts_at: rfc3339.to_string(),
        }
    }

    #[test]
    fn context_uses_bio_even_without_address() {
        let profile = ProviderProfile {
            bio: Some("Esthétique dentaire, blanchiment, facettes. Opéra / 9e.".to_string()),
            sector: Some("1".to_string()),
            tiers_payant: Some(true),
            pmr: Some(true),
            ..mk_profile()
        };
        let context = render_context(&profile, "Dr Amélie Dubois", "");
        assert_eq!(
            context,
            "Esthétique dentaire, blanchiment, facettes. Opéra / 9e."
        );
    }

    #[test]
    fn context_falls_back_to_city_sentence_without_bio() {
        let profile = ProviderProfile {
            sector: Some("2".to_string()),
            ..mk_profile()
        };
        let context = render_context(&profile, "Dr Hugo Marin", "Lyon");
        assert!(context.contains("exerce en secteur 2 à Lyon"));
    }

    #[test]
    fn context_falls_back_to_tautology_when_nothing_else_is_known() {
        let profile = mk_profile();
        let context = render_context(&profile, "Dr Amélie Dubois", "");
        assert_eq!(context, "Profil du praticien Dr Amélie Dubois.");
    }

    /// #6791, point 1 de l'audit : les faits pratiques doivent être des
    /// badges structurés, pas une phrase de prose.
    #[test]
    fn badges_cover_sector_tiers_payant_new_patients_and_pmr() {
        let profile = ProviderProfile {
            sector: Some("1".to_string()),
            tiers_payant: Some(true),
            accepts_new_patients: Some(true),
            pmr: Some(true),
            ..mk_profile()
        };
        let badges = render_badges(&profile);
        assert!(badges.contains("Secteur 1 — tarifs conventionnés"));
        assert!(badges.contains("Tiers payant"));
        assert!(badges.contains("Nouveaux patients acceptés"));
        assert!(badges.contains("Accès PMR"));
    }

    #[test]
    fn badges_are_empty_when_nothing_is_known() {
        assert_eq!(render_badges(&mk_profile()), "");
    }

    /// #6791, point 2 de l'audit : bandeau "Prochaine disponibilité" dérivé
    /// du 1er créneau, sans créneau → aucun bandeau (pas de valeur
    /// fabriquée).
    #[test]
    fn next_availability_is_empty_without_any_slot() {
        assert_eq!(render_next_availability(Uuid::nil(), None), "");
    }

    #[test]
    fn next_availability_renders_a_cta_with_the_slot() {
        let now = Utc::now();
        let slot = SlotRef {
            slot_id: Uuid::nil(),
            starts_at: now.to_rfc3339(),
        };
        let html = render_next_availability(Uuid::nil(), Some(&slot));
        assert!(html.contains("Prochaine disponibilité"));
        assert!(html.contains("Aujourd'hui"));
        assert!(html.contains("Prendre rendez-vous"));
    }

    /// #6791, point 4 de l'audit (root cause du bug « 165 puces en vrac ») :
    /// la grille semaine ne doit montrer QUE les 6 jours (lun-sam) de la
    /// semaine sélectionnée, pas tous les jours à créneaux d'affilée.
    #[test]
    fn agenda_week_shows_only_six_days_of_the_selected_week() {
        let slots = (0..12)
            .map(|d| slot_at(&format!("2026-09-{:02}T09:00:00Z", 10 + d)))
            .collect::<Vec<_>>();
        let html = render_agenda_week(Uuid::nil(), &slots, 0);
        assert_eq!(html.matches(r#"class="day""#).count(), 6);
    }

    #[test]
    fn agenda_week_pads_empty_days_with_a_dash() {
        let slots = vec![slot_at("2026-09-10T09:00:00Z")]; // Jeudi
        let html = render_agenda_week(Uuid::nil(), &slots, 0);
        assert!(html.contains(r#"<span class="chip off">—</span>"#));
    }

    #[test]
    fn agenda_week_next_chevron_links_to_the_following_week() {
        let slots = (0..12)
            .map(|d| slot_at(&format!("2026-09-{:02}T09:00:00Z", 10 + d)))
            .collect::<Vec<_>>();
        let html = render_agenda_week(Uuid::nil(), &slots, 0);
        assert!(html.contains(r#"href="?semaine=1""#));
    }

    #[test]
    fn agenda_week_falls_back_explicitly_without_any_slot() {
        let html = render_agenda_week(Uuid::nil(), &[], 0);
        assert!(html.contains("Aucun créneau en ligne"));
    }

    /// #6791, point 5 de l'audit : adresse connue → rendue ; adresse absente
    /// (cas réel pour le praticien de démo de l'issue) → repli explicite,
    /// pas un bloc muet.
    #[test]
    fn access_section_renders_establishment_and_address_when_known() {
        let profile = ProviderProfile {
            establishment_name: Some("Cabinet Nubia Opéra".to_string()),
            address: Some(
                serde_json::json!({"rue": "12 rue de la Paix", "cp": "75002", "ville": "Paris"}),
            ),
            ..mk_profile()
        };
        let html = render_access_section(&profile);
        assert!(html.contains("Cabinet Nubia Opéra"));
        assert!(html.contains("12 rue de la Paix"));
        assert!(html.contains("75002"));
    }

    #[test]
    fn access_section_falls_back_explicitly_without_an_address() {
        let html = render_access_section(&mk_profile());
        assert!(html.contains("Non communiquée en ligne"));
    }
}
