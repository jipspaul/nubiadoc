import 'package:nubia_domain/src/entities/lab_stats.dart';

class LabStatActItemDto {
  final String labWorkOrderId;
  final String labName;
  final String? practitionerId;
  final String? practitionerName;
  final String? toothFdi;
  final String? workNature;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatActItemDto({
    required this.labWorkOrderId,
    required this.labName,
    this.practitionerId,
    this.practitionerName,
    this.toothFdi,
    this.workNature,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  factory LabStatActItemDto.fromJson(Map<String, dynamic> json) =>
      LabStatActItemDto(
        labWorkOrderId: json['lab_work_order_id'] as String,
        labName: json['lab_name'] as String,
        practitionerId: json['practitioner_id'] as String?,
        practitionerName: json['practitioner_name'] as String?,
        toothFdi: json['tooth_fdi'] as String?,
        workNature: json['work_nature'] as String?,
        labCostCents: json['lab_cost_cents'] as int,
        patientRevenueCents: json['patient_revenue_cents'] as int,
        marginCents: json['margin_cents'] as int,
      );

  LabStatActItem toDomain() => LabStatActItem(
        labWorkOrderId: labWorkOrderId,
        labName: labName,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        toothFdi: toothFdi,
        workNature: workNature,
        labCostCents: labCostCents,
        patientRevenueCents: patientRevenueCents,
        marginCents: marginCents,
      );
}

class LabStatByLabDto {
  final String labName;
  final int orderCount;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatByLabDto({
    required this.labName,
    required this.orderCount,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  factory LabStatByLabDto.fromJson(Map<String, dynamic> json) =>
      LabStatByLabDto(
        labName: json['lab_name'] as String,
        orderCount: json['order_count'] as int,
        labCostCents: json['lab_cost_cents'] as int,
        patientRevenueCents: json['patient_revenue_cents'] as int,
        marginCents: json['margin_cents'] as int,
      );

  LabStatByLab toDomain() => LabStatByLab(
        labName: labName,
        orderCount: orderCount,
        labCostCents: labCostCents,
        patientRevenueCents: patientRevenueCents,
        marginCents: marginCents,
      );
}

class LabStatByPractitionerDto {
  final String practitionerId;
  final String? practitionerName;
  final int orderCount;
  final int labCostCents;
  final int patientRevenueCents;
  final int marginCents;

  const LabStatByPractitionerDto({
    required this.practitionerId,
    this.practitionerName,
    required this.orderCount,
    required this.labCostCents,
    required this.patientRevenueCents,
    required this.marginCents,
  });

  factory LabStatByPractitionerDto.fromJson(Map<String, dynamic> json) =>
      LabStatByPractitionerDto(
        practitionerId: json['practitioner_id'] as String,
        practitionerName: json['practitioner_name'] as String?,
        orderCount: json['order_count'] as int,
        labCostCents: json['lab_cost_cents'] as int,
        patientRevenueCents: json['patient_revenue_cents'] as int,
        marginCents: json['margin_cents'] as int,
      );

  LabStatByPractitioner toDomain() => LabStatByPractitioner(
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        orderCount: orderCount,
        labCostCents: labCostCents,
        patientRevenueCents: patientRevenueCents,
        marginCents: marginCents,
      );
}

class LabStatsDto {
  final String periodMonth;
  final int totalLabCostCents;
  final int totalPatientRevenueCents;
  final int totalMarginCents;
  final List<LabStatActItemDto> byAct;
  final List<LabStatByPractitionerDto> byPractitioner;
  final List<LabStatByLabDto> byLab;

  const LabStatsDto({
    required this.periodMonth,
    required this.totalLabCostCents,
    required this.totalPatientRevenueCents,
    required this.totalMarginCents,
    required this.byAct,
    required this.byPractitioner,
    required this.byLab,
  });

  factory LabStatsDto.fromJson(Map<String, dynamic> json) => LabStatsDto(
        periodMonth: json['period_month'] as String,
        totalLabCostCents: json['total_lab_cost_cents'] as int,
        totalPatientRevenueCents: json['total_patient_revenue_cents'] as int,
        totalMarginCents: json['total_margin_cents'] as int,
        byAct: (json['by_act'] as List<dynamic>)
            .map((e) => LabStatActItemDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        byPractitioner: (json['by_practitioner'] as List<dynamic>)
            .map((e) =>
                LabStatByPractitionerDto.fromJson(e as Map<String, dynamic>))
            .toList(),
        byLab: (json['by_lab'] as List<dynamic>)
            .map((e) => LabStatByLabDto.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  LabStats toDomain() => LabStats(
        periodMonth: periodMonth,
        totalLabCostCents: totalLabCostCents,
        totalPatientRevenueCents: totalPatientRevenueCents,
        totalMarginCents: totalMarginCents,
        byAct: byAct.map((d) => d.toDomain()).toList(),
        byPractitioner: byPractitioner.map((d) => d.toDomain()).toList(),
        byLab: byLab.map((d) => d.toDomain()).toList(),
      );
}
