// Quoi : formateurs et calculs partagés par les sous-vues de la consultation
// au fauteuil (date courte, heure courte, total en centimes).
// Quand : appelé depuis `consultation_clinique_page.dart` et les widgets
// extraits (`act_tile.dart`, `side_column.dart`, `patient_identity_bar.dart`,
// `acts_of_session_card.dart`, `consultation_historique_view.dart`) pour
// éviter de dupliquer ces formats.
// Pourquoi : ces fonctions étaient répétées identiquement à plusieurs
// endroits du fichier monolithique d'origine — regroupées ici pour garantir
// un format unique (#3402 pour le total, #4937/#4943/#4945/#4950 pour les
// formats de date/heure).
// Modes d'échec : aucun — fonctions pures, sans état ni I/O.
import 'package:nubia_domain/nubia_domain.dart';

/// Somme des montants des actes de la séance (#3402) — source unique
/// réutilisée par la barre d'identité (`PatientIdentityBar`) et le pied de
/// liste des actes (`ActsOfSessionCard`) pour garantir un total identique
/// aux deux endroits.
int sessionTotalCents(ClinicalSession session) =>
    session.acts.fold<int>(0, (sum, act) => sum + (act.amountCents ?? 0));

/// Heure courte HH:MM (24 h, heure locale) — format imposé par la maquette
/// design-v2 pour l'indicateur d'auto-save de la note (#4943) et l'horaire
/// des actes de la séance (#4950).
String formatTime(DateTime dt) {
  final d = dt.toLocal();
  final hh = d.hour.toString().padLeft(2, '0');
  final min = d.minute.toString().padLeft(2, '0');
  return '$hh:$min';
}

/// Date courte JJ/MM (heure locale) — réutilisée par `HistoriqueView` et par
/// `RecentSessionsBox` (#4937, encart « Dernières séances ») pour éviter de
/// dupliquer le format de date.
String formatShortDate(DateTime dt) {
  final d = dt.toLocal();
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$dd/$mm';
}
