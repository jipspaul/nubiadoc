//! Normalisation ASCII kebab-case (accents français repliés) — même table
//! que le repli d'accents SQL de `marketplace::search_providers`
//! (`translate(..., 'àâäéèêëïîôöùûüçñ', 'aaaeeeeiioouuucn')`), pour que les
//! slugs générés ici restent cohérents avec la recherche full-text
//! existante.
const ACCENTS: &[(char, char)] = &[
    ('à', 'a'),
    ('â', 'a'),
    ('ä', 'a'),
    ('é', 'e'),
    ('è', 'e'),
    ('ê', 'e'),
    ('ë', 'e'),
    ('ï', 'i'),
    ('î', 'i'),
    ('ô', 'o'),
    ('ö', 'o'),
    ('ù', 'u'),
    ('û', 'u'),
    ('ü', 'u'),
    ('ç', 'c'),
    ('ñ', 'n'),
];

/// Ex. `"Dr Amélie Rousseau Chirurgien-dentiste Paris"` → `"dr-amelie-rousseau-chirurgien-dentiste-paris"`.
pub fn slugify(input: &str) -> String {
    let mut out = String::with_capacity(input.len());
    let mut last_dash = false;
    for ch in input.to_lowercase().chars() {
        let folded = ACCENTS
            .iter()
            .find(|(a, _)| *a == ch)
            .map(|(_, b)| *b)
            .unwrap_or(ch);
        if folded.is_ascii_alphanumeric() {
            out.push(folded);
            last_dash = false;
        } else if !last_dash && !out.is_empty() {
            out.push('-');
            last_dash = true;
        }
    }
    out.trim_end_matches('-').to_string()
}

#[cfg(test)]
mod tests {
    use super::slugify;

    #[test]
    fn folds_accents_and_kebab_cases() {
        assert_eq!(
            slugify("Dr Amélie Rousseau Chirurgien-dentiste Paris"),
            "dr-amelie-rousseau-chirurgien-dentiste-paris"
        );
    }

    #[test]
    fn collapses_repeated_separators_without_leading_or_trailing_dash() {
        assert_eq!(slugify("  Dr  Hugo   Marin — Lyon "), "dr-hugo-marin-lyon");
    }
}
