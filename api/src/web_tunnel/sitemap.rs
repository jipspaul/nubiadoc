//! `GET /sitemap.xml` — XML, pas la page HTML « Praticien introuvable »
//! (#6720), même défaut de routage que `robots.rs`. Amorce de crawl réelle,
//! pas une liste statique inventée : les fiches praticien viennent de
//! `marketplace::search_providers`, la MÊME fonction que la page de
//! recherche et l'API publique (#5355) — aucune requête dupliquée.

use axum::extract::{Query, State};
use axum::http::header;
use axum::response::IntoResponse;
use axum::Json;

use crate::marketplace::{search_providers, ProviderItem, SearchProvidersQuery};
use crate::AppState;

use super::html::tunnel_base_url;
use super::provider_page::slug_for;

/// Les deux professions de premier niveau que le tunnel sait traiter comme
/// pages de recherche — mêmes slugs que `related_specialty_slug`/
/// `specialty_plural_label` (`search_page.rs`) : ce ne sont pas les
/// `specialty.label` de la base (« Omnipratique », « Implantologie », …),
/// qui n'ont pas de correspondance fiable vers un slug de recherche.
const TOP_LEVEL_SPECIALTIES: &[&str] = &["dentiste", "orthodontiste"];

/// Localités du bloc de maillage (`locality::paris_neighbours`, `search_page.rs`)
/// — même périmètre volontairement restreint (« Paris uniquement, schéma en
/// escargot ») plutôt qu'un catalogue exhaustif : aucune table de localités
/// n'existe côté marketplace pour en dériver une liste réelle, cf.
/// `locality.rs`. `lyon` reprend la ville déjà présente dans les fixtures de
/// démo (`db/seed/seed.sql`).
const KNOWN_LOCALITIES: &[&str] = &[
    "paris",
    "paris-1er",
    "paris-2e",
    "paris-3e",
    "paris-4e",
    "paris-5e",
    "paris-6e",
    "paris-7e",
    "paris-8e",
    "paris-9e",
    "paris-10e",
    "paris-11e",
    "paris-12e",
    "paris-13e",
    "paris-14e",
    "paris-15e",
    "paris-16e",
    "paris-17e",
    "paris-18e",
    "paris-19e",
    "paris-20e",
    "lyon",
];

/// Borne dure sur le nombre de fiches praticien listées (#6720) : un
/// sitemap n'a pas vocation à paginer indéfiniment, et cette route n'est pas
/// authentifiée — sans borne, une base très peuplée en ferait une requête de
/// coût arbitraire.
const MAX_PROVIDER_URLS: usize = 2000;

pub async fn sitemap_xml(State(state): State<AppState>) -> impl IntoResponse {
    let base = tunnel_base_url();
    let mut urls = static_urls(&base);
    urls.extend(listed_provider_urls(state, &base).await);

    (
        [(header::CONTENT_TYPE, "application/xml; charset=utf-8")],
        render_sitemap_xml(&urls),
    )
}

/// Racine + pages spécialité × localité connues (#6720) : sans elles, un
/// crawler n'a aucune amorce pour découvrir `/dentiste/paris-2e` — le
/// maillage interne (`maillage_links`) ne relie ces pages qu'ENTRE elles,
/// pas depuis l'extérieur.
fn static_urls(base: &str) -> Vec<String> {
    let mut urls = vec![format!("{base}/")];
    for specialty in TOP_LEVEL_SPECIALTIES {
        for locality in KNOWN_LOCALITIES {
            urls.push(format!("{base}/{specialty}/{locality}"));
        }
    }
    urls
}

fn provider_urls(providers: &[ProviderItem], base: &str) -> Vec<String> {
    providers
        .iter()
        .map(|p| {
            let href = slug_for(&p.display_name, p.specialty.as_deref(), None);
            format!("{base}/{href}")
        })
        .collect()
}

/// Pagine `search_providers` (par 100, plafond `per_page`) jusqu'à couvrir
/// `page.total` ou atteindre [`MAX_PROVIDER_URLS`].
async fn listed_provider_urls(state: AppState, base: &str) -> Vec<String> {
    let mut urls = Vec::new();
    let mut page_num = 1i64;
    loop {
        let params = SearchProvidersQuery {
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
            page: Some(page_num),
            per_page: Some(100),
            provider_id: None,
            date: None,
        };
        let Ok(Json(resp)) = search_providers(State(state.clone()), Query(params)).await else {
            break;
        };
        let got = resp.data.len();
        urls.extend(provider_urls(&resp.data, base));
        let covered = page_num * 100;
        if got < 100 || urls.len() >= MAX_PROVIDER_URLS || covered >= resp.page.total {
            break;
        }
        page_num += 1;
    }
    urls.truncate(MAX_PROVIDER_URLS);
    urls
}

fn render_sitemap_xml(urls: &[String]) -> String {
    let entries = urls
        .iter()
        .map(|u| format!("<url><loc>{}</loc></url>", super::html::escape(u)))
        .collect::<Vec<_>>()
        .join("\n");
    format!(
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
         <urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n{entries}\n</urlset>\n"
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use uuid::Uuid;

    #[test]
    fn static_urls_includes_root_and_known_specialty_locality_pairs() {
        let urls = static_urls("https://reservation.doc.nubia-link.com");
        assert!(urls.contains(&"https://reservation.doc.nubia-link.com/".to_string()));
        assert!(
            urls.contains(&"https://reservation.doc.nubia-link.com/dentiste/paris-2e".to_string())
        );
        assert!(
            urls.contains(&"https://reservation.doc.nubia-link.com/orthodontiste/lyon".to_string())
        );
    }

    #[test]
    fn provider_urls_reuses_the_same_slug_as_search_page_cards() {
        let providers = vec![ProviderItem {
            provider_id: Uuid::nil(),
            display_name: "Dr Amélie Dubois".to_string(),
            specialty: Some("Omnipratique".to_string()),
            sector: None,
            distance_m: None,
            next_slot_at: None,
            rating_avg: None,
            geo: None,
            is_listed: true,
            tiers_payant: None,
            pmr: None,
            accepts_new_patients: None,
        }];
        let urls = provider_urls(&providers, "https://reservation.doc.nubia-link.com");
        assert_eq!(
            urls,
            vec![
                "https://reservation.doc.nubia-link.com/dr-amelie-dubois-omnipratique".to_string()
            ]
        );
    }

    #[test]
    fn render_sitemap_xml_wraps_each_url_and_escapes_it() {
        let xml = render_sitemap_xml(&["https://x/a?b=1&c=2".to_string()]);
        assert!(xml.starts_with("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"));
        assert!(xml.contains("<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"));
        assert!(xml.contains("<url><loc>https://x/a?b=1&amp;c=2</loc></url>"));
    }
}
