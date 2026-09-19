import 'package:nubia_domain/nubia_domain.dart';

class KpiAmountsDto {
  final int billedCents;
  final int collectedCents;

  const KpiAmountsDto({
    required this.billedCents,
    required this.collectedCents,
  });

  factory KpiAmountsDto.fromJson(Map<String, dynamic> json) => KpiAmountsDto(
        billedCents: json['billed_cents'] as int,
        collectedCents: json['collected_cents'] as int,
      );

  PractitionerKpiAmounts toDomain() => PractitionerKpiAmounts(
        billedCents: billedCents,
        collectedCents: collectedCents,
      );
}

class CabinetKpiItemDto {
  final String cabinetId;
  final String? cabinetName;
  final KpiAmountsDto today;
  final KpiAmountsDto month;
  final int appointmentsToday;
  final int pendingReminders;
  final double? occupancyRate;
  final int? objectiveTargetCents;
  final double? objectiveAchievedPct;

  const CabinetKpiItemDto({
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

  factory CabinetKpiItemDto.fromJson(Map<String, dynamic> json) =>
      CabinetKpiItemDto(
        cabinetId: json['cabinet_id'] as String,
        cabinetName: json['cabinet_name'] as String?,
        today: KpiAmountsDto.fromJson(json['today'] as Map<String, dynamic>),
        month: KpiAmountsDto.fromJson(json['month'] as Map<String, dynamic>),
        appointmentsToday: json['appointments_today'] as int,
        pendingReminders: json['pending_reminders'] as int,
        occupancyRate: (json['occupancy_rate'] as num?)?.toDouble(),
        objectiveTargetCents: json['objective_target_cents'] as int?,
        objectiveAchievedPct:
            (json['objective_achieved_pct'] as num?)?.toDouble(),
      );

  CabinetKpiSummary toDomain() => CabinetKpiSummary(
        cabinetId: cabinetId,
        cabinetName: cabinetName,
        today: today.toDomain(),
        month: month.toDomain(),
        appointmentsToday: appointmentsToday,
        pendingReminders: pendingReminders,
        occupancyRate: occupancyRate,
        objectiveTargetCents: objectiveTargetCents,
        objectiveAchievedPct: objectiveAchievedPct,
      );
}

class PractitionerKpisDto {
  final String periodMonth;
  final KpiAmountsDto today;
  final KpiAmountsDto month;
  final int appointmentsToday;
  final int pendingReminders;
  final double? occupancyRate;
  final int? objectiveTargetCents;
  final double? objectiveAchievedPct;
  final List<CabinetKpiItemDto> byCabinet;

  const PractitionerKpisDto({
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

  factory PractitionerKpisDto.fromJson(Map<String, dynamic> json) =>
      PractitionerKpisDto(
        periodMonth: json['period_month'] as String,
        today: KpiAmountsDto.fromJson(json['today'] as Map<String, dynamic>),
        month: KpiAmountsDto.fromJson(json['month'] as Map<String, dynamic>),
        appointmentsToday: json['appointments_today'] as int,
        pendingReminders: json['pending_reminders'] as int,
        occupancyRate: (json['occupancy_rate'] as num?)?.toDouble(),
        objectiveTargetCents: json['objective_target_cents'] as int?,
        objectiveAchievedPct:
            (json['objective_achieved_pct'] as num?)?.toDouble(),
        byCabinet: (json['by_cabinet'] as List<dynamic>? ?? [])
            .map((e) => CabinetKpiItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  PractitionerKpis toDomain() => PractitionerKpis(
        periodMonth: periodMonth,
        today: today.toDomain(),
        month: month.toDomain(),
        appointmentsToday: appointmentsToday,
        pendingReminders: pendingReminders,
        occupancyRate: occupancyRate,
        objectiveTargetCents: objectiveTargetCents,
        objectiveAchievedPct: objectiveAchievedPct,
        byCabinet: byCabinet.map((e) => e.toDomain()).toList(),
      );
}
