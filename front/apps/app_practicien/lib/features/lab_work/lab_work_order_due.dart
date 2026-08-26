import 'package:flutter/foundation.dart';

const _kWeekdayNames = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// Tonalité du repère de délai affiché en pied de carte (couleur/icône côté
/// widget) : gris à l'heure, ambre bientôt dû, rouge en retard.
enum LabWorkOrderDueTone { onTime, soon, overdue }

/// Repère de délai lisible affiché en pied de carte d'un bon actif
/// (ex. « Attendu le 21/08 », « Attendu jeudi », « Retard de 2 j »),
/// maquette design-v2 point 2 (#5059) : « rien ne dit quand la pièce
/// revient, alors que c'est la raison d'ouvrir cet écran ».
@immutable
class LabWorkOrderDue {
  const LabWorkOrderDue(this.label, this.tone);

  final String label;
  final LabWorkOrderDueTone tone;
}

/// Calcule le repère de délai d'un bon à partir de sa date de retour
/// attendue (`expectedReturnAt`, ISO 8601, nullable) et de son [status], à
/// l'heure [now] (injectée pour rester une fonction pure testable).
///
/// - Bon `fitted`, ou pas de date attendue → pas de repère (`null`), pas de
///   crash.
/// - Date dépassée → « Retard de N j », ton [LabWorkOrderDueTone.overdue] —
///   même prédicat (date dépassée, statut pas encore `fitted`) que
///   `computeLabWorkOrderMetrics`/`_isOverdue` dans `lab_work_orders_page.dart`.
/// - Date le jour même → « Attendu aujourd'hui ».
/// - Date dans les 7 prochains jours → « Attendu jeudi » (jour de la semaine), ton
///   [LabWorkOrderDueTone.soon] — même fenêtre que le compteur « attendus
///   cette semaine ».
/// - Au-delà → « Attendu le JJ/MM », ton [LabWorkOrderDueTone.onTime].
LabWorkOrderDue? labWorkOrderDueOf({
  required String status,
  required String? expectedReturnAt,
  required DateTime now,
}) {
  if (status == 'fitted' || expectedReturnAt == null) return null;
  final expected = DateTime.parse(expectedReturnAt);

  if (expected.isBefore(now)) {
    final days = _dayDiff(expected, now);
    return LabWorkOrderDue(
      'Retard de ${days < 1 ? 1 : days} j',
      LabWorkOrderDueTone.overdue,
    );
  }
  if (_dayDiff(expected, now) == 0) {
    return const LabWorkOrderDue(
      "Attendu aujourd'hui",
      LabWorkOrderDueTone.soon,
    );
  }
  if (expected.isBefore(now.add(const Duration(days: 7)))) {
    return LabWorkOrderDue(
      'Attendu ${_weekdayName(expected)}',
      LabWorkOrderDueTone.soon,
    );
  }
  return LabWorkOrderDue(
    'Attendu le ${_shortDate(expected)}',
    LabWorkOrderDueTone.onTime,
  );
}

int _dayDiff(DateTime date, DateTime now) {
  final d = DateTime(date.year, date.month, date.day);
  final n = DateTime(now.year, now.month, now.day);
  return n.difference(d).inDays;
}

String _weekdayName(DateTime date) => _kWeekdayNames[date.weekday - 1];

String _shortDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month';
}
