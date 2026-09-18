//! Gardes temporelles du cycle de vie d'un RDV (#6770, #6912, #6875).
//!
//! Un seul endroit pour les règles « quand peut-on faire quoi » sur un RDV,
//! partagé par le check-in (patient ET cabinet, tous modes : QR / app /
//! manuel) et par le démarrage de séance (`start_consultation`). Avant, ces
//! règles étaient dispersées et se contredisaient : le check-in patient
//! appliquait `starts_at ± 60 min`, le check-in cabinet une fenêtre
//! glissante `now() ± 1 jour` (#7248) et `start` sautait sa fenêtre dès que le
//! RDV était `checked_in` — un RDV de demain (ou de 2027) passait donc
//! `confirmed → checked_in → in_progress → done` sans qu'aucune garde ne se
//! déclenche (#6770, #6912).
//!
//! Règles (documentées dans `docs/12-api-reference.md` §13) :
//!
//! - **Check-in patient** (`POST /v1/appointments/:id/checkin`) :
//!   `starts_at − 60 min ≤ now ≤ starts_at + 60 min` (inchangé, #3844).
//! - **Check-in cabinet** (`POST /v1/cabinet/appointments/:id/checkin`) :
//!   `starts_at − 2 h ≤ now ≤ ends_at + 1 h`. Le secrétariat constate une
//!   présence physique et a donc plus de latitude qu'un patient (arrivée en
//!   avance, retardataire), mais toujours le **jour du créneau** — la
//!   fenêtre contient celle du patient.
//! - **Démarrage de séance** (`POST /v1/cabinet/appointments/:id/start`) :
//!   quel que soit le statut d'entrée, `now ≥ starts_at − 2 h` (même borne
//!   basse que le check-in cabinet — un patient arrivé en avance et déjà
//!   enregistré peut passer au fauteuil, cf. #6875/#4396). Depuis `confirmed`
//!   (démarrage direct sans check-in), la fenêtre `± 60 min` reste en plus
//!   appliquée (#3822).
//!
//! Trop tôt → `409 too_early` ; trop tard → `409 out_of_window`.
//!
//! Il n'y a volontairement PAS de garde « avant `starts_at` » sur la clôture
//! (`complete`) : la séance n'existe que via `start`, et clôturer avant
//! l'heure du créneau un patient arrivé en avance est un cas normal du
//! comptoir (#6875). Un RDV `done` dont `starts_at` est encore futur doit
//! alors rester visible dans l'onglet « passés » (`appointments_read.rs`).

use chrono::{DateTime, Duration, Utc};

use crate::auth::AppError;

/// Marge (minutes) de part et d'autre de `starts_at` pour le check-in
/// patient (#3844).
pub const PATIENT_CHECKIN_MARGIN_MIN: i64 = 60;

/// Avance maximale (minutes) avant `starts_at` pour le check-in cabinet et le
/// démarrage de séance d'un patient déjà enregistré.
pub const CABINET_CHECKIN_EARLY_MARGIN_MIN: i64 = 120;

/// Retard maximal (minutes) après `ends_at` pour le check-in cabinet.
pub const CABINET_CHECKIN_LATE_MARGIN_MIN: i64 = 60;

/// Fenêtre du check-in patient : `starts_at ± 60 min`.
pub fn check_patient_checkin_window(
    now: DateTime<Utc>,
    starts_at: DateTime<Utc>,
) -> Result<(), AppError> {
    let margin = Duration::minutes(PATIENT_CHECKIN_MARGIN_MIN);
    if now < starts_at - margin {
        return Err(AppError::TooEarly);
    }
    if now > starts_at + margin {
        return Err(AppError::OutOfWindow);
    }
    Ok(())
}

/// Fenêtre du check-in cabinet : `[starts_at − 2 h, ends_at + 1 h]`.
pub fn check_cabinet_checkin_window(
    now: DateTime<Utc>,
    starts_at: DateTime<Utc>,
    ends_at: DateTime<Utc>,
) -> Result<(), AppError> {
    if now < starts_at - Duration::minutes(CABINET_CHECKIN_EARLY_MARGIN_MIN) {
        return Err(AppError::TooEarly);
    }
    if now > ends_at + Duration::minutes(CABINET_CHECKIN_LATE_MARGIN_MIN) {
        return Err(AppError::OutOfWindow);
    }
    Ok(())
}

/// Fenêtre du démarrage de séance, selon le statut d'entrée du RDV.
///
/// - `confirmed` (démarrage direct, sans check-in) : `starts_at ± 60 min`
///   (#3822), la même que le check-in patient.
/// - `checked_in` / `in_progress` (patient présent, enregistré par lui-même
///   ou par le comptoir, éventuellement appelé via call-next) : borne basse
///   `starts_at − 2 h` uniquement — sans elle, un check-in cabinet qui
///   aurait échappé à sa propre fenêtre (donnée legacy, #6770) suffisait à
///   ouvrir puis clôturer une séance sur un RDV de 2027.
pub fn check_start_window(
    now: DateTime<Utc>,
    starts_at: DateTime<Utc>,
    status: &str,
) -> Result<(), AppError> {
    if status == "confirmed" {
        return check_patient_checkin_window(now, starts_at);
    }
    if now < starts_at - Duration::minutes(CABINET_CHECKIN_EARLY_MARGIN_MIN) {
        return Err(AppError::TooEarly);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn t(minutes_from_now: i64) -> DateTime<Utc> {
        Utc::now() + Duration::minutes(minutes_from_now)
    }

    #[test]
    fn patient_window_is_plus_minus_60_min() {
        let now = Utc::now();
        assert!(check_patient_checkin_window(now, t(-59)).is_ok());
        assert!(check_patient_checkin_window(now, t(59)).is_ok());
        assert!(matches!(
            check_patient_checkin_window(now, t(61)),
            Err(AppError::TooEarly)
        ));
        assert!(matches!(
            check_patient_checkin_window(now, t(-61)),
            Err(AppError::OutOfWindow)
        ));
    }

    #[test]
    fn cabinet_window_is_minus_2h_to_end_plus_1h() {
        let now = Utc::now();
        // Créneaux de 30 min.
        assert!(check_cabinet_checkin_window(now, t(119), t(149)).is_ok());
        assert!(check_cabinet_checkin_window(now, t(-89), t(-59)).is_ok());
        assert!(matches!(
            check_cabinet_checkin_window(now, t(121), t(151)),
            Err(AppError::TooEarly)
        ));
        // RDV de demain, même heure.
        assert!(matches!(
            check_cabinet_checkin_window(now, t(24 * 60), t(24 * 60 + 30)),
            Err(AppError::TooEarly)
        ));
        // RDV dans 15 mois.
        assert!(matches!(
            check_cabinet_checkin_window(now, t(15 * 30 * 24 * 60), t(15 * 30 * 24 * 60 + 30)),
            Err(AppError::TooEarly)
        ));
        assert!(matches!(
            check_cabinet_checkin_window(now, t(-91), t(-61)),
            Err(AppError::OutOfWindow)
        ));
    }

    #[test]
    fn cabinet_window_contains_patient_window() {
        let now = Utc::now();
        for m in [-60, -30, 0, 30, 60] {
            // Créneau d'une minute : le pire cas pour la borne haute.
            assert!(check_cabinet_checkin_window(now, t(m), t(m + 1)).is_ok());
        }
    }

    #[test]
    fn start_window_confirmed_is_plus_minus_60_min() {
        let now = Utc::now();
        assert!(check_start_window(now, t(59), "confirmed").is_ok());
        assert!(matches!(
            check_start_window(now, t(61), "confirmed"),
            Err(AppError::TooEarly)
        ));
        assert!(matches!(
            check_start_window(now, t(-61), "confirmed"),
            Err(AppError::OutOfWindow)
        ));
    }

    #[test]
    fn start_window_checked_in_refuses_tomorrow_but_accepts_early_arrival() {
        let now = Utc::now();
        for status in ["checked_in", "in_progress"] {
            assert!(check_start_window(now, t(119), status).is_ok());
            assert!(check_start_window(now, t(-24 * 60), status).is_ok());
            assert!(matches!(
                check_start_window(now, t(20 * 60), status),
                Err(AppError::TooEarly)
            ));
        }
    }
}
