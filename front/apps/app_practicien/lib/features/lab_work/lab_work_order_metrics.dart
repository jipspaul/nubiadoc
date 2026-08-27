import 'package:nubia_domain/nubia_domain.dart';

/// Agrégats de la bande d'en-tête « Travaux labo » (#5063, point 7 de la
/// maquette) : onze bons, aucun total, aucun filtre — quatre compteurs
/// suffisent à répondre aux questions du matin.
class LabWorkOrderMetrics {
  const LabWorkOrderMetrics({
    required this.inProgressCount,
    required this.overdueCount,
    required this.dueThisWeekCount,
    required this.committedCents,
  });

  /// Bons non `fitted` (encore actifs chez le labo ou en essayage).
  final int inProgressCount;

  /// Bons actifs dont la date de retour attendue est dépassée.
  final int overdueCount;

  /// Bons actifs dont la date de retour attendue tombe dans les 7 prochains
  /// jours (retards exclus).
  final int dueThisWeekCount;

  /// Somme des `purchasePriceCents` des bons en cours.
  final int committedCents;
}

/// Calcule [LabWorkOrderMetrics] à partir de la liste des bons et de l'heure
/// courante [now] (injectée pour rester une fonction pure testable).
LabWorkOrderMetrics computeLabWorkOrderMetrics(
  List<LabWorkOrder> orders, {
  required DateTime now,
}) {
  final inProgress = orders.where((o) => o.status != 'fitted').toList();
  final weekFromNow = now.add(const Duration(days: 7));

  var overdueCount = 0;
  var dueThisWeekCount = 0;
  var committedCents = 0;

  for (final order in inProgress) {
    committedCents += order.purchasePriceCents;

    final expectedReturnAt = order.expectedReturnAt;
    if (expectedReturnAt == null) continue;
    final expected = DateTime.parse(expectedReturnAt);

    if (expected.isBefore(now)) {
      overdueCount++;
    } else if (expected.isBefore(weekFromNow)) {
      dueThisWeekCount++;
    }
  }

  return LabWorkOrderMetrics(
    inProgressCount: inProgress.length,
    overdueCount: overdueCount,
    dueThisWeekCount: dueThisWeekCount,
    committedCents: committedCents,
  );
}
