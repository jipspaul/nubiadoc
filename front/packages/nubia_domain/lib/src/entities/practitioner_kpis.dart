import 'package:equatable/equatable.dart';

/// Montants facturé/encaissé d'une période (jour ou mois), en centimes.
class PractitionerKpiAmounts extends Equatable {
  final int billedCents;
  final int collectedCents;

  const PractitionerKpiAmounts({
    required this.billedCents,
    required this.collectedCents,
  });

  @override
  List<Object?> get props => [billedCents, collectedCents];
}

/// KPI d'un praticien pour un cabinet donné (élément de
/// [PractitionerKpis.byCabinet], praticien multi-cabinet).
class CabinetKpiSummary extends Equatable {
  final String cabinetId;
  final String? cabinetName;
  final PractitionerKpiAmounts today;
  final PractitionerKpiAmounts month;
  final int appointmentsToday;
  final int pendingReminders;

  /// Créneaux réservés / créneaux ouverts de la semaine courante. `null` si
  /// aucun créneau ouvert cette semaine (rien à diviser).
  final double? occupancyRate;
  final int? objectiveTargetCents;
  final double? objectiveAchievedPct;

  const CabinetKpiSummary({
    required this.cabinetId,
    this.cabinetName,
    required this.today,
    required this.month,
    required this.appointmentsToday,
    required this.pendingReminders,
    this.occupancyRate,
    this.objectiveTargetCents,
    this.objectiveAchievedPct,
  });

  @override
  List<Object?> get props => [
        cabinetId,
        cabinetName,
        today,
        month,
        appointmentsToday,
        pendingReminders,
        occupancyRate,
        objectiveTargetCents,
        objectiveAchievedPct,
      ];
}

/// Tableau de bord KPI du praticien connecté (#7189, DP-F10.b) :
/// `GET /v1/me/kpis?period=YYYY-MM`, agrégé sur tous ses cabinets et détaillé
/// par cabinet ([byCabinet]) pour les praticiens multi-cabinet.
class PractitionerKpis extends Equatable {
  /// Premier jour du mois utilisé pour `month`/l'objectif (`YYYY-MM-DD`).
  final String periodMonth;
  final PractitionerKpiAmounts today;
  final PractitionerKpiAmounts month;
  final int appointmentsToday;
  final int pendingReminders;
  final double? occupancyRate;
  final int? objectiveTargetCents;
  final double? objectiveAchievedPct;
  final List<CabinetKpiSummary> byCabinet;

  const PractitionerKpis({
    required this.periodMonth,
    required this.today,
    required this.month,
    required this.appointmentsToday,
    required this.pendingReminders,
    this.occupancyRate,
    this.objectiveTargetCents,
    this.objectiveAchievedPct,
    required this.byCabinet,
  });

  @override
  List<Object?> get props => [
        periodMonth,
        today,
        month,
        appointmentsToday,
        pendingReminders,
        occupancyRate,
        objectiveTargetCents,
        objectiveAchievedPct,
        byCabinet,
      ];
}
