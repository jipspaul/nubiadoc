//! Échappement HTML + layout partagé des pages SSR du tunnel — #5356.

use axum::response::Html;

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
"#;

pub fn page(title: &str, body: &str) -> Html<String> {
    Html(format!(
        r#"<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title>
<style>{css}</style>
</head>
<body>
<div class="wrap">
{body}
</div>
</body>
</html>"#,
        css = NUBIA_CSS,
    ))
}

#[cfg(test)]
mod tests {
    use super::escape;

    #[test]
    fn escapes_html_special_characters() {
        assert_eq!(
            escape(r#"<script>"O'Brien" & co</script>"#),
            "&lt;script&gt;&quot;O&#39;Brien&quot; &amp; co&lt;/script&gt;"
        );
    }
}
