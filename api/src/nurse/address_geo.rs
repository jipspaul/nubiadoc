//! Cohérence GPS (`lat`/`lng`) vs `address` saisie sur une demande de visite (#7430).
//!
//! Contexte : `visit_geo` (utilisé par le fan-out `ST_DWithin`) vient du GPS de
//! l'appareil, tandis que `address` (celle vue par l'infirmière à l'écran) est
//! un `jsonb` jamais validé sur le fond. Sans géocodeur externe disponible dans
//! ce backend, on détecte au moins l'incohérence *manifeste* : le point GPS
//! doit tomber à une distance raisonnable du département du code postal
//! déclaré. Un centroïde de département (préfecture) suffit à cet usage — on
//! ne cherche pas une précision de géocodage, seulement à refuser un couple
//! du type « GPS à Lyon, adresse à Paris » (~390 km).

/// Centroïde approximatif (préfecture) par code département — codes
/// métropolitains à 2 chiffres (Corse regroupée sous "20") + DOM à 3 chiffres.
const DEPARTMENT_CENTROIDS: &[(&str, f64, f64)] = &[
    ("01", 46.20, 5.23),
    ("02", 49.56, 3.62),
    ("03", 46.57, 3.33),
    ("04", 44.09, 6.24),
    ("05", 44.56, 6.08),
    ("06", 43.70, 7.27),
    ("07", 44.74, 4.60),
    ("08", 49.77, 4.72),
    ("09", 42.97, 1.61),
    ("10", 48.30, 4.08),
    ("11", 43.21, 2.35),
    ("12", 44.35, 2.57),
    ("13", 43.30, 5.37),
    ("14", 49.18, -0.37),
    ("15", 44.93, 2.44),
    ("16", 45.65, 0.16),
    ("17", 46.16, -1.15),
    ("18", 47.08, 2.40),
    ("19", 45.27, 1.77),
    ("20", 42.20, 9.05),
    ("21", 47.32, 5.04),
    ("22", 48.51, -2.77),
    ("23", 46.17, 1.87),
    ("24", 45.18, 0.72),
    ("25", 47.24, 6.02),
    ("26", 44.93, 4.89),
    ("27", 49.03, 1.15),
    ("28", 48.45, 1.49),
    ("29", 47.10, -4.10),
    ("30", 43.84, 4.36),
    ("31", 43.60, 1.44),
    ("32", 43.65, 0.59),
    ("33", 44.84, -0.58),
    ("34", 43.61, 3.88),
    ("35", 48.11, -1.68),
    ("36", 46.81, 1.69),
    ("37", 47.39, 0.69),
    ("38", 45.19, 5.72),
    ("39", 46.67, 5.55),
    ("40", 43.89, -0.50),
    ("41", 47.59, 1.33),
    ("42", 45.44, 4.39),
    ("43", 45.04, 3.88),
    ("44", 47.22, -1.55),
    ("45", 47.90, 1.90),
    ("46", 44.45, 1.44),
    ("47", 44.20, 0.62),
    ("48", 44.52, 3.50),
    ("49", 47.47, -0.55),
    ("50", 49.11, -1.09),
    ("51", 48.96, 4.36),
    ("52", 48.11, 5.14),
    ("53", 48.07, -0.77),
    ("54", 48.69, 6.18),
    ("55", 48.77, 5.16),
    ("56", 47.66, -2.76),
    ("57", 49.12, 6.18),
    ("58", 46.99, 3.16),
    ("59", 50.63, 3.06),
    ("60", 49.43, 2.08),
    ("61", 48.43, 0.09),
    ("62", 50.29, 2.78),
    ("63", 45.78, 3.08),
    ("64", 43.30, -0.37),
    ("65", 43.23, 0.08),
    ("66", 42.70, 2.90),
    ("67", 48.58, 7.75),
    ("68", 48.08, 7.36),
    ("69", 45.76, 4.84),
    ("70", 47.62, 6.15),
    ("71", 46.31, 4.83),
    ("72", 48.00, 0.20),
    ("73", 45.56, 5.92),
    ("74", 45.90, 6.13),
    ("75", 48.86, 2.35),
    ("76", 49.44, 1.10),
    ("77", 48.54, 2.66),
    ("78", 48.80, 2.13),
    ("79", 46.32, -0.46),
    ("80", 49.90, 2.30),
    ("81", 43.93, 2.15),
    ("82", 44.02, 1.35),
    ("83", 43.12, 5.93),
    ("84", 43.95, 4.81),
    ("85", 46.67, -1.43),
    ("86", 46.58, 0.34),
    ("87", 45.83, 1.26),
    ("88", 48.17, 6.45),
    ("89", 47.80, 3.57),
    ("90", 47.64, 6.86),
    ("91", 48.63, 2.43),
    ("92", 48.89, 2.20),
    ("93", 48.91, 2.44),
    ("94", 48.79, 2.46),
    ("95", 49.04, 2.08),
    ("971", 16.27, -61.55),
    ("972", 14.64, -61.02),
    ("973", 4.94, -52.33),
    ("974", -21.12, 55.53),
    ("976", -12.78, 45.23),
];

/// Distance au-delà de laquelle un couple (GPS, code postal) est considéré
/// manifestement incohérent. Généreux (plus large que le plus grand
/// département métropolitain) pour ne jamais rejeter un cas légitime, mais
/// bien plus petit que des écarts inter-régions comme Paris↔Lyon (~390 km).
const MAX_PLAUSIBLE_DISTANCE_KM: f64 = 150.0;

fn extract_postal_code(address: &serde_json::Value) -> Option<&str> {
    address.get("postal_code")?.as_str()
}

/// Code département ("01".."95", "20" pour la Corse, "971".."976" pour les DOM)
/// déduit d'un code postal français à 5 chiffres. `None` si le format ne
/// correspond pas (pas de quoi bloquer une adresse étrangère ou mal saisie).
fn department_code(postal_code: &str) -> Option<&'static str> {
    let digits: String = postal_code.chars().filter(char::is_ascii_digit).collect();
    if digits.len() != 5 {
        return None;
    }
    let prefix3 = &digits[0..3];
    if let Some((code, _, _)) = DEPARTMENT_CENTROIDS
        .iter()
        .find(|(c, _, _)| c.len() == 3 && *c == prefix3)
    {
        return Some(*code);
    }
    let prefix2 = &digits[0..2];
    DEPARTMENT_CENTROIDS
        .iter()
        .find(|(c, _, _)| c.len() == 2 && *c == prefix2)
        .map(|(code, _, _)| *code)
}

fn haversine_km(lat1: f64, lng1: f64, lat2: f64, lng2: f64) -> f64 {
    const EARTH_RADIUS_KM: f64 = 6371.0;
    let (lat1r, lat2r) = (lat1.to_radians(), lat2.to_radians());
    let dlat = (lat2 - lat1).to_radians();
    let dlng = (lng2 - lng1).to_radians();
    let a = (dlat / 2.0).sin().powi(2) + lat1r.cos() * lat2r.cos() * (dlng / 2.0).sin().powi(2);
    EARTH_RADIUS_KM * 2.0 * a.sqrt().asin()
}

/// `true` si le point GPS fourni tombe à une distance déraisonnable du
/// département du code postal déclaré dans `address`. Ne rejette que les cas
/// manifestes : code postal absent/illisible ou département non reconnu →
/// `false` (on ne bloque pas faute de donnée fiable).
pub(crate) fn is_manifestly_inconsistent(lat: f64, lng: f64, address: &serde_json::Value) -> bool {
    let Some(postal_code) = extract_postal_code(address) else {
        return false;
    };
    let Some(dept) = department_code(postal_code) else {
        return false;
    };
    let Some((_, dept_lat, dept_lng)) = DEPARTMENT_CENTROIDS.iter().find(|(c, _, _)| *c == dept)
    else {
        return false;
    };
    haversine_km(lat, lng, *dept_lat, *dept_lng) > MAX_PLAUSIBLE_DISTANCE_KM
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn detects_paris_address_with_lyon_gps() {
        let address =
            json!({"line1": "45 Avenue Montaigne", "city": "Paris", "postal_code": "75008"});
        // GPS de Lyon (cf. QA-20260920-R86-4, #7430)
        assert!(is_manifestly_inconsistent(45.75, 4.85, &address));
    }

    #[test]
    fn accepts_matching_lyon_address_and_gps() {
        let address =
            json!({"line1": "10 rue de la Santé", "city": "Lyon", "postal_code": "69003"});
        assert!(!is_manifestly_inconsistent(45.75, 4.85, &address));
    }

    #[test]
    fn accepts_gps_near_department_border() {
        // Versailles (78) déclaré, GPS pris à Paris intra-muros : même
        // agglomération, ne doit jamais être rejeté.
        let address =
            json!({"line1": "1 place d'Armes", "city": "Versailles", "postal_code": "78000"});
        assert!(!is_manifestly_inconsistent(48.86, 2.35, &address));
    }

    #[test]
    fn ignores_missing_postal_code() {
        let address = json!({"line1": "45 Avenue Montaigne", "city": "Paris"});
        assert!(!is_manifestly_inconsistent(45.75, 4.85, &address));
    }

    #[test]
    fn ignores_unrecognized_postal_code() {
        let address = json!({"line1": "1 foreign st", "city": "Nowhere", "postal_code": "00000"});
        assert!(!is_manifestly_inconsistent(45.75, 4.85, &address));
    }
}
