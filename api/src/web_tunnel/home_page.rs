//! `GET /` — accueil du tunnel (#6720) : avant ce correctif, la racine ne
//! portait aucune route et Axum répondait `404` avec un corps vide (aucun
//! contenu, aucun lien, aucune amorce de crawl). Vitrine minimale — mêmes
//! specialités/localités de premier niveau que `sitemap.rs`, pour donner à
//! un visiteur (humain ou moteur) un point d'entrée réel vers les pages de
//! recherche.

use axum::response::Html;

use super::html::{escape, page, PageMeta};

const LINKS: [(&str, &str); 3] = [
    ("Chirurgiens-dentistes à Paris", "/dentiste/paris"),
    ("Chirurgiens-dentistes à Lyon", "/dentiste/lyon"),
    ("Orthodontistes à Paris", "/orthodontiste/paris"),
];

const DESCRIPTION: &str = "Nubia référence des chirurgiens-dentistes et orthodontistes acceptant la prise de rendez-vous en ligne, avec les tarifs conventionnés et les créneaux disponibles en temps réel.";

pub async fn home_page() -> Html<String> {
    let links_html = LINKS
        .iter()
        .map(|(label, href)| {
            format!(
                r#"<a class="lk" href="{href}">{label}</a>"#,
                href = escape(href),
                label = escape(label),
            )
        })
        .collect::<Vec<_>>()
        .join("\n");

    let body = format!(
        r#"<h1>Trouvez un praticien et prenez rendez-vous en ligne</h1>
<div class="context">
  <p>{description}</p>
</div>
<nav class="seo" aria-label="Spécialités et villes">
{links_html}
</nav>"#,
        description = escape(DESCRIPTION),
    );

    let meta = PageMeta::new(DESCRIPTION, "/");
    page(
        "Nubia — Prendre rendez-vous avec un praticien près de chez vous",
        &meta,
        &body,
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn renders_a_real_h1_and_links_to_search_pages() {
        let Html(html) = home_page().await;
        assert!(html.contains("<h1>Trouvez un praticien et prenez rendez-vous en ligne</h1>"));
        assert!(html.contains(r#"href="/dentiste/paris""#));
        assert!(html.contains(r#"<meta name="description" content=""#));
    }
}
