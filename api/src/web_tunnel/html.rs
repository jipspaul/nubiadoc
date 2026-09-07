//! Échappement HTML + layout partagé des pages SSR du tunnel — #5356.
//!
//! #6720 : le tunnel est « la seule surface Nubia dont l'unique raison
//! d'être est d'être trouvée » (ADR-013, `docs/04-architecture.md`) mais
//! `page()` ne posait jusqu'ici aucun des signaux qui font qu'une page se
//! classe — [`PageMeta`] les rend obligatoires pour tout appelant.

use axum::response::Html;

/// URL publique du tunnel — `TUNNEL_BASE_URL` (déploiement), sinon le
/// domaine réel de prod (`infra/deploy/README.md`, bloc Caddy
/// `reservation.doc.nubia-link.com`). Sert de base aux URL absolues
/// (canonical, Open Graph, sitemap) : ces balises doivent porter l'URL
/// publique même quand le process écoute en HTTP interne derrière le proxy.
pub fn tunnel_base_url() -> String {
    std::env::var("TUNNEL_BASE_URL")
        .unwrap_or_else(|_| "https://reservation.doc.nubia-link.com".to_string())
}

/// Signaux SEO d'une page (#6720) : description, canonical, Open Graph et
/// JSON-LD optionnel. `robots`/`og_type` par défaut couvrent le cas commun
/// (page indexable, type `website`) ; `provider_page` bascule `og_type` sur
/// `profile`, `confirm_page`/le 404 praticien basculent `robots` sur
/// `noindex` (pages transactionnelles ou sans contenu propre à classer).
pub struct PageMeta {
    pub description: String,
    pub canonical_path: String,
    pub og_type: &'static str,
    pub robots: &'static str,
    pub json_ld: Option<String>,
}

impl PageMeta {
    pub fn new(description: impl Into<String>, canonical_path: impl Into<String>) -> Self {
        Self {
            description: truncate_description(&description.into()),
            canonical_path: canonical_path.into(),
            og_type: "website",
            robots: "index, follow",
            json_ld: None,
        }
    }

    pub fn og_type(mut self, og_type: &'static str) -> Self {
        self.og_type = og_type;
        self
    }

    pub fn robots(mut self, robots: &'static str) -> Self {
        self.robots = robots;
        self
    }

    pub fn json_ld(mut self, json_ld: String) -> Self {
        self.json_ld = Some(json_ld);
        self
    }
}

/// Coupe au dernier espace avant 160 caractères (longueur usuelle affichée
/// par les moteurs) plutôt qu'en plein milieu d'un mot.
fn truncate_description(text: &str) -> String {
    const MAX: usize = 160;
    if text.chars().count() <= MAX {
        return text.to_string();
    }
    let truncated: String = text.chars().take(MAX).collect();
    match truncated.rfind(' ') {
        Some(idx) => format!("{}…", &truncated[..idx]),
        None => format!("{truncated}…"),
    }
}

pub fn escape(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    for ch in input.chars() {
        match ch {
            '&' => out.push_str("&amp;"),
            '<' => out.push_str("&lt;"),
            '>' => out.push_str("&gt;"),
            '"' => out.push_str("&quot;"),
            '\'' => out.push_str("&#39;"),
            _ => out.push(ch),
        }
    }
    out
}

/// Jetons transposés depuis `nubia_design_system` (émeraude/stone) — brand600
/// `#059669` (identité), échelle `n*` (fond/texte/bordures), Fraunces
/// réservée aux titres comme côté Flutter (`nubia_theme.dart` : « Tout est
/// Inter sauf `display` en Fraunces »). Valeurs : `01-tokens.md` §1.4/§1.5 et
/// `nubia_colors.dart`.
pub const NUBIA_CSS: &str = r#"
:root {
  --brand-600: #059669;
  --brand-700: #047857;
  --brand-50: #ECFDF5;
  --n-50: #FAFAF9;
  --n-100: #F5F5F4;
  --n-200: #E7E5E4;
  --n-400: #A8A29E;
  --n-600: #57534E;
  --n-900: #1C1917;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--n-50);
  color: var(--n-900);
  font-family: Inter, system-ui, sans-serif;
  line-height: 1.5;
}
h1, h2 { font-family: Fraunces, Georgia, serif; font-weight: 600; margin: 0 0 .5rem; }
h1 { font-size: 2rem; }
h2 { font-size: 1.25rem; }
a { color: var(--brand-700); }
.wrap { max-width: 960px; margin: 0 auto; padding: 1.5rem; }
.context { background: #fff; border: 1px solid var(--n-200); border-radius: 12px; padding: 1.25rem 1.5rem; margin: 1.5rem 0; }
.seo { margin-top: 2rem; }
.seo .lk { display: inline-block; margin: .25rem .75rem .25rem 0; padding: .35rem .75rem; border: 1px solid var(--n-200); border-radius: 999px; text-decoration: none; font-size: .875rem; }
.card { background: #fff; border: 1px solid var(--n-200); border-radius: 12px; padding: 1rem 1.25rem; margin-bottom: 1rem; }
.card h3 { margin: 0 0 .25rem; font-family: Inter, sans-serif; font-size: 1.05rem; }
.muted { color: var(--n-600); font-size: .9rem; }
.tags { margin: .5rem 0 0; }
.tag { display: inline-block; font-size: .75rem; font-weight: 600; background: var(--n-100); color: var(--n-600); border-radius: 6px; padding: .15rem .5rem; margin: 0 .35rem .35rem 0; }
.slots { display: flex; gap: .5rem; margin-top: .75rem; flex-wrap: wrap; }
.day { flex: 1 1 0; min-width: 90px; }
.dlabel { display: block; font-size: .75rem; font-weight: 600; color: var(--n-600); margin-bottom: .35rem; }
.chip { display: inline-block; font-size: .8rem; font-weight: 600; background: var(--brand-50); color: var(--brand-700); border: 1px solid var(--n-200); border-radius: 6px; padding: .25rem .5rem; margin: 0 .25rem .25rem 0; text-decoration: none; }
.more { display: block; font-size: .8rem; font-weight: 600; margin-top: .25rem; }
.nosl { background: var(--n-50); border: 1px dashed var(--n-200); border-radius: 8px; padding: .6rem .75rem; margin-top: .75rem; }
"#;

pub fn page(title: &str, meta: &PageMeta, body: &str) -> Html<String> {
    let title = escape(title);
    let description = escape(&meta.description);
    let canonical_url = escape(&format!("{}{}", tunnel_base_url(), meta.canonical_path));
    // `</script>` dans une valeur JSON fermerait prématurément la balise —
    // même échappement que la doc MDN pour du JSON-LD inline.
    let json_ld_block = meta
        .json_ld
        .as_deref()
        .map(|json| {
            format!(
                r#"<script type="application/ld+json">{}</script>"#,
                json.replace("</", "<\\/")
            )
        })
        .unwrap_or_default();
    Html(format!(
        r#"<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<meta name="description" content="{description}">
<meta name="robots" content="{robots}">
<link rel="canonical" href="{canonical_url}">
<meta property="og:type" content="{og_type}">
<meta property="og:title" content="{title}">
<meta property="og:description" content="{description}">
<meta property="og:url" content="{canonical_url}">
<meta property="og:locale" content="fr_FR">
{json_ld_block}
<style>{css}</style>
</head>
<body>
<div class="wrap">
{body}
</div>
</body>
</html>"#,
        robots = meta.robots,
        og_type = meta.og_type,
        css = NUBIA_CSS,
    ))
}

#[cfg(test)]
mod tests {
    use super::{escape, page, truncate_description, PageMeta};

    #[test]
    fn escapes_html_special_characters() {
        assert_eq!(
            escape(r#"<script>"O'Brien" & co</script>"#),
            "&lt;script&gt;&quot;O&#39;Brien&quot; &amp; co&lt;/script&gt;"
        );
    }

    #[test]
    fn truncate_description_leaves_short_text_untouched() {
        assert_eq!(
            truncate_description("Courte description."),
            "Courte description."
        );
    }

    #[test]
    fn truncate_description_cuts_at_a_word_boundary_under_160_chars() {
        let long = "mot ".repeat(60); // 240 caractères
        let truncated = truncate_description(&long);
        assert!(truncated.chars().count() <= 161, "{truncated}");
        assert!(truncated.ends_with('…'));
        assert!(!truncated.trim_end_matches('…').ends_with(' '));
    }

    #[test]
    fn page_emits_description_canonical_og_and_robots() {
        let meta = PageMeta::new("Une description", "/dentiste/paris-2e").og_type("profile");
        let html = page("Titre — Nubia", &meta, "<h1>Titre</h1>").0;
        assert!(html.contains(r#"<meta name="description" content="Une description">"#));
        assert!(html.contains(
            r#"<link rel="canonical" href="https://reservation.doc.nubia-link.com/dentiste/paris-2e">"#
        ));
        assert!(html.contains(r#"<meta property="og:type" content="profile">"#));
        assert!(html.contains(r#"<meta property="og:title" content="Titre — Nubia">"#));
        assert!(html.contains(r#"<meta name="robots" content="index, follow">"#));
    }

    #[test]
    fn page_defaults_to_indexable_and_website() {
        let meta = PageMeta::new("desc", "/");
        let html = page("T", &meta, "").0;
        assert!(html.contains(r#"<meta name="robots" content="index, follow">"#));
        assert!(html.contains(r#"<meta property="og:type" content="website">"#));
        assert!(!html.contains("application/ld+json"));
    }

    #[test]
    fn page_can_carry_noindex_robots() {
        let meta = PageMeta::new("desc", "/reservation/confirmer").robots("noindex, follow");
        let html = page("T", &meta, "").0;
        assert!(html.contains(r#"<meta name="robots" content="noindex, follow">"#));
    }

    #[test]
    fn page_embeds_json_ld_and_escapes_script_close_sequences() {
        let meta = PageMeta::new("desc", "/x").json_ld(r#"{"a":"</script>"}"#.to_string());
        let html = page("T", &meta, "").0;
        assert!(html.contains(r#"<script type="application/ld+json">"#));
        assert!(!html.contains("</script>\"}"));
    }

    #[test]
    fn page_escapes_title_in_both_title_tag_and_og_title() {
        let meta = PageMeta::new("desc", "/x");
        let html = page("<script>alert(1)</script>", &meta, "").0;
        assert!(!html.contains("<title><script>"));
        assert!(html.contains("&lt;script&gt;alert(1)&lt;/script&gt;"));
    }
}
