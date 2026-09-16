//! Parsing/formatage des slugs de localité (`paris-2e`, `paris-1er`,
//! `lyon`) et adjacence géographique des arrondissements parisiens, pour le
//! bloc de maillage `.seo` de la page de recherche — #5356.

pub struct Locality {
    pub city_slug: String,
    pub city_label: String,
    pub arrondissement: Option<u32>,
}

pub fn parse(slug: &str) -> Locality {
    if let Some((city_part, suffix)) = slug.rsplit_once('-') {
        let digits: String = suffix.chars().take_while(|c| c.is_ascii_digit()).collect();
        let rest = &suffix[digits.len()..];
        if !digits.is_empty() && (rest == "e" || rest == "er") {
            if let Ok(n) = digits.parse::<u32>() {
                return Locality {
                    city_slug: city_part.to_string(),
                    city_label: titleize(city_part),
                    arrondissement: Some(n),
                };
            }
        }
    }
    Locality {
        city_slug: slug.to_string(),
        city_label: titleize(slug),
        arrondissement: None,
    }
}

pub fn titleize(slug: &str) -> String {
    slug.split('-')
        .filter(|w| !w.is_empty())
        .map(|w| {
            let mut chars = w.chars();
            match chars.next() {
                Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

/// `1` → `"1er"`, `2` → `"2e"`, etc.
pub fn ordinal(n: u32) -> String {
    if n == 1 {
        "1er".to_string()
    } else {
        format!("{n}e")
    }
}

pub fn label(loc: &Locality) -> String {
    match loc.arrondissement {
        Some(n) => format!("{} {}", loc.city_label, ordinal(n)),
        None => loc.city_label.clone(),
    }
}

/// Reconstruit le slug complet (`paris` + `Some(2)` → `"paris-2e"`) — inverse
/// de [`parse`], utilisé pour générer les URL du bloc de maillage.
pub fn slug_of(loc: &Locality) -> String {
    match loc.arrondissement {
        Some(n) => format!("{}-{}", loc.city_slug, ordinal(n)),
        None => loc.city_slug.clone(),
    }
}

/// Adjacence réelle des arrondissements parisiens (numérotation en
/// escargot). Seuls les 2 premiers de chaque ligne sont affichés dans le
/// maillage (maquette `patient-web-tunnel-reservation.png`, bloc `.seo` :
/// « Dentiste Paris 1er » + « Dentiste Paris 9e » pour le 2e — l'ordre de
/// chaque ligne place donc délibérément ces 2 voisins en tête pour le 2e).
const PARIS_ADJACENCY: &[(u32, &[u32])] = &[
    (1, &[2, 3, 4, 5, 6, 7, 8]),
    (2, &[1, 9, 3, 10]),
    (3, &[1, 2, 4, 10, 11]),
    (4, &[3, 5, 11, 12]),
    (5, &[4, 6, 13, 14]),
    (6, &[5, 7, 14, 15]),
    (7, &[1, 6, 8, 15, 16]),
    (8, &[1, 7, 9, 17]),
    (9, &[2, 8, 10, 17, 18]),
    (10, &[2, 3, 9, 11, 19]),
    (11, &[3, 4, 10, 12, 19, 20]),
    (12, &[4, 11, 20]),
    (13, &[5, 14]),
    (14, &[5, 6, 13, 15]),
    (15, &[6, 7, 14, 16]),
    (16, &[7, 8, 15, 17]),
    (17, &[8, 9, 16, 18]),
    (18, &[9, 17, 19]),
    (19, &[10, 11, 18, 20]),
    (20, &[11, 12, 19]),
];

pub fn paris_neighbours(arrondissement: u32) -> Vec<u32> {
    PARIS_ADJACENCY
        .iter()
        .find(|(n, _)| *n == arrondissement)
        .map(|(_, neighbours)| neighbours.iter().take(2).copied().collect())
        .unwrap_or_default()
}

/// Centroïde (lat, lng) de chaque mairie d'arrondissement parisien —
/// utilisé pour filtrer `search_providers` par proximité réelle sur les
/// pages `/dentiste/paris-Ne` (#7049) : `search_page.rs` ne passait jusque là
/// que `place=paris` (rayon ville, 20 km), l'arrondissement parsé était
/// jeté avant la requête et les 20 pages d'arrondissement d'une spécialité
/// servaient toutes la même liste que `/dentiste/paris`.
const PARIS_ARRONDISSEMENT_CENTERS: &[(u32, f64, f64)] = &[
    (1, 48.8626, 2.3363),
    (2, 48.8688, 2.3411),
    (3, 48.8630, 2.3600),
    (4, 48.8534, 2.3579),
    (5, 48.8445, 2.3471),
    (6, 48.8496, 2.3335),
    (7, 48.8561, 2.3122),
    (8, 48.8718, 2.3079),
    (9, 48.8767, 2.3376),
    (10, 48.8760, 2.3600),
    (11, 48.8592, 2.3800),
    (12, 48.8352, 2.3862),
    (13, 48.8322, 2.3560),
    (14, 48.8323, 2.3255),
    (15, 48.8422, 2.2933),
    (16, 48.8637, 2.2769),
    (17, 48.8874, 2.3072),
    (18, 48.8925, 2.3444),
    (19, 48.8871, 2.3831),
    (20, 48.8632, 2.4009),
];

/// Coordonnées du centre d'un arrondissement parisien, ou `None` s'il n'est
/// pas répertorié (ville hors Paris, ou `arrondissement` hors 1-20).
pub fn paris_arrondissement_center(arrondissement: u32) -> Option<(f64, f64)> {
    PARIS_ARRONDISSEMENT_CENTERS
        .iter()
        .find(|(n, _, _)| *n == arrondissement)
        .map(|(_, lat, lng)| (*lat, *lng))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_arrondissement_suffix() {
        let loc = parse("paris-2e");
        assert_eq!(loc.city_slug, "paris");
        assert_eq!(loc.city_label, "Paris");
        assert_eq!(loc.arrondissement, Some(2));
        assert_eq!(label(&loc), "Paris 2e");
        assert_eq!(slug_of(&loc), "paris-2e");
    }

    #[test]
    fn parses_1er_ordinal() {
        let loc = parse("paris-1er");
        assert_eq!(loc.arrondissement, Some(1));
        assert_eq!(label(&loc), "Paris 1er");
    }

    #[test]
    fn falls_back_to_city_only_without_arrondissement_suffix() {
        let loc = parse("lyon");
        assert_eq!(loc.city_slug, "lyon");
        assert_eq!(loc.arrondissement, None);
        assert_eq!(label(&loc), "Lyon");
        assert_eq!(slug_of(&loc), "lyon");
    }

    #[test]
    fn paris_2e_neighbours_match_the_mockup() {
        assert_eq!(paris_neighbours(2), vec![1, 9]);
    }

    /// #7049 : chacun des 20 arrondissements doit résoudre un centre, et
    /// des arrondissements différents doivent résoudre des centres
    /// différents — c'est ce qui permet à `search_page::geo_params_for` de
    /// filtrer réellement par arrondissement plutôt que de retomber sur la
    /// même recherche « toute la ville » pour les 20 pages.
    #[test]
    fn paris_arrondissement_center_resolves_all_20_distinctly() {
        let centers: Vec<(f64, f64)> = (1..=20)
            .map(|n| paris_arrondissement_center(n).unwrap_or_else(|| panic!("arrondissement {n} sans centre")))
            .collect();
        for i in 0..centers.len() {
            for j in (i + 1)..centers.len() {
                assert_ne!(centers[i], centers[j], "arrondissements {} et {} partagent un centre", i + 1, j + 1);
            }
        }
    }

    #[test]
    fn paris_arrondissement_center_is_none_outside_1_to_20() {
        assert_eq!(paris_arrondissement_center(21), None);
        assert_eq!(paris_arrondissement_center(0), None);
    }
}
