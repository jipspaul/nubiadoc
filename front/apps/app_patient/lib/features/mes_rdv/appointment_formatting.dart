/// Helpers de formatage partagés par les cartes de rendez-vous.
///
/// Quoi : dérive les initiales d'un praticien (avatar) et le libellé
/// date/heure court affiché sur une carte (#5260, extrait de
/// `_AppointmentCard`).
///
/// Quand : appelé à chaque `build` de carte — logique pure, aucune I/O.
///
/// Pourquoi : préparer la refonte visuelle (rail de date, initiales) qui
/// réutilise cette logique ailleurs que dans `_AppointmentCard`, sans
/// dupliquer le code.
///
/// Modes d'échec : aucun — [appointmentInitials] retourne `'?'` sur une
/// chaîne vide/blanche, [formatAppointmentDateTime] n'a pas d'entrée
/// invalide possible (`DateTime` toujours valide).
library;

import 'package:characters/characters.dart';

/// Initiales dérivées de [name], sans le préfixe de civilité éventuel
/// (« Dr », « Dr. », « Pr », « Pr. », « M. », « Mme », « Mlle ») :
/// « Dr Amélie Dubois » → « AD » (et non « DD »).
String appointmentInitials(String name) {
  // Retire le préfixe de civilité (« Dr », « Dr. », « Pr », « M. »…) pour ne
  // pas polluer les initiales : « Dr Amélie Dubois » → « AD », pas « DD ».
  final cleaned = name
      .replaceAll(
        RegExp(r'^(Dr|Dr\.|Pr|Pr\.|M\.|Mme|Mlle)\s+', caseSensitive: false),
        '',
      )
      .trim();
  final parts =
      cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }
  return (parts.first.characters.first + parts.last.characters.first)
      .toUpperCase();
}

/// Libellé date/heure court (« Lun 3 fév à 09:30 ») dérivé de [utc], un
/// horodatage UTC (`DateTime.parse()` sur un ISO +00:00, `isUtc == true`).
///
/// #4620/#4618 : lire `.hour`/`.day`/`.weekday` bruts sur [utc] affichait
/// l'heure UTC au lieu de l'heure locale (-2h en été / -1h en hiver pour
/// Europe/Paris) — [utc] est donc converti via `.toLocal()` avant tout accès.
String formatAppointmentDateTime(DateTime utc) {
  const weekdays = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
  const months = [
    'jan',
    'fév',
    'mar',
    'avr',
    'mai',
    'jun',
    'jul',
    'aoû',
    'sep',
    'oct',
    'nov',
    'déc',
  ];
  final dt = utc.toLocal();
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '${weekdays[dt.weekday - 1]} ${dt.day} ${months[dt.month - 1]} à $h:$m';
}
