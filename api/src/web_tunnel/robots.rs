//! `GET /robots.txt` — texte, pas la page HTML « Praticien introuvable »
//! (#6720) : sans route explicite, `/robots.txt` était avalé par le
//! catch-all `/:slug` de `provider_page` (aucun praticien nommé « robots.txt »
//! n'existe, donc 404 HTML).

use axum::http::header;
use axum::response::IntoResponse;

use super::html::tunnel_base_url;

/// Pas de `Disallow` sur `/reservation/confirmer` : cette page est déjà
/// `noindex` via sa balise `<meta name="robots">` (`confirm_page.rs`) — un
/// `Disallow` ici empêcherait justement les moteurs de crawler la page pour
/// lire cette balise (recommandation Google : laisser crawler une page
/// `noindex`, ne pas la bloquer par `robots.txt`).
pub async fn robots_txt() -> impl IntoResponse {
    let body = format!(
        "User-agent: *\nAllow: /\n\nSitemap: {}/sitemap.xml\n",
        tunnel_base_url(),
    );
    ([(header::CONTENT_TYPE, "text/plain; charset=utf-8")], body)
}
