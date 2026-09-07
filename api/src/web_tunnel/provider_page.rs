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
    get_provider, search_providers, search_slots, ProviderProfile, SearchProvidersQuery, SlotRef,
};
use crate::AppState;

use super::html::{escape, page, tunnel_base_url, PageMeta};
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
        return not_found(&slug);
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
        accepts_new_patients: None,
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
        accepts_new_patients: None,
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

    let context = render_context(&profile, &h1, city);

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

/// Paragraphe de contexte de la fiche praticien (#6721) : la `bio` quand
/// elle existe (texte le plus riche disponible), sinon repli sur "exerce à
/// {city}" quand une adresse est connue, sinon la tautologie minimale — puis
/// dans tous les cas les faits pratiques déjà servis par l'API (secteur,
/// tiers payant, accès PMR) que la maquette affiche en badges.
fn render_context(profile: &ProviderProfile, h1: &str, city: &str) -> String {
    let intro = match profile.bio.as_deref().map(str::trim) {
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
    };

    let mut facts = Vec::new();
    if let Some(sector) = profile.sector.as_deref() {
        facts.push(format!("Secteur {}", escape(sector)));
    }
    if profile.tiers_payant.unwrap_or(false) {
        facts.push("tiers payant accepté".to_string());
    }
    if profile.pmr.unwrap_or(false) {
        facts.push("accès PMR".to_string());
    }

    if facts.is_empty() {
        intro
    } else {
        format!("{intro} {}.", facts.join(" · "))
    }
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
            establishment_id: None,
            rating_avg: None,
            review_count: 0,
        }
    }

    #[test]
    fn context_uses_bio_and_facts_even_without_address() {
        let profile = ProviderProfile {
            bio: Some("Esthétique dentaire, blanchiment, facettes. Opéra / 9e.".to_string()),
            sector: Some("1".to_string()),
            tiers_payant: Some(true),
            pmr: Some(true),
            ..mk_profile()
        };
        let context = render_context(&profile, "Dr Amélie Dubois", "");
        assert!(context.contains("Esthétique dentaire"));
        assert!(context.contains("Secteur 1"));
        assert!(context.contains("tiers payant accepté"));
        assert!(context.contains("accès PMR"));
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
}
