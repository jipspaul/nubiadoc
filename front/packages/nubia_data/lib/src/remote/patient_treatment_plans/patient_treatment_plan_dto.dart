import 'package:nubia_domain/src/entities/patient_treatment_plan.dart';

class PatientTreatmentPlanItemDto {
  final String label;
  final String? ccamCode;
  final int unitAmountCents;
  final int amoPartCents;
  final int amcPartCents;

  const PatientTreatmentPlanItemDto({
    required this.label,
    this.ccamCode,
    required this.unitAmountCents,
    required this.amoPartCents,
    required this.amcPartCents,
  });

  factory PatientTreatmentPlanItemDto.fromJson(Map<String, dynamic> json) =>
      PatientTreatmentPlanItemDto(
        label: json['label'] as String,
        ccamCode: json['ccam_code'] as String?,
        unitAmountCents: json['unit_amount_cents'] as int,
        amoPartCents: json['amo_part_cents'] as int,
        amcPartCents: json['amc_part_cents'] as int,
      );

  PatientTreatmentPlanItem toDomain() => PatientTreatmentPlanItem(
        label: label,
        ccamCode: ccamCode,
        unitAmountCents: unitAmountCents,
        amoPartCents: amoPartCents,
        amcPartCents: amcPartCents,
      );
}

class PatientTreatmentPlanPhaseDto {
  final String id;
  final int position;
  final String title;
  final String status;
  final List<PatientTreatmentPlanItemDto> items;
  final String? pendingQuoteId;
  final String? pendingQuoteSentAt;

  const PatientTreatmentPlanPhaseDto({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.items = const [],
    this.pendingQuoteId,
    this.pendingQuoteSentAt,
  });

  factory PatientTreatmentPlanPhaseDto.fromJson(Map<String, dynamic> json) =>
      PatientTreatmentPlanPhaseDto(
        id: json['id'] as String,
        position: json['position'] as int,
        title: json['title'] as String,
        status: json['status'] as String,
        items: (json['items'] as List<dynamic>?)
                ?.map((e) => PatientTreatmentPlanItemDto.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            const [],
        pendingQuoteId: json['pending_quote_id'] as String?,
        pendingQuoteSentAt: json['pending_quote_sent_at'] as String?,
      );

  PatientTreatmentPlanPhase toDomain() => PatientTreatmentPlanPhase(
        id: id,
        position: position,
        title: title,
        status: status,
        items: items.map((i) => i.toDomain()).toList(),
        pendingQuoteId: pendingQuoteId,
        pendingQuoteSentAt: pendingQuoteSentAt != null
            ? DateTime.parse(pendingQuoteSentAt!)
            : null,
      );
}

class PatientTreatmentPlanDto {
  final String id;
  final String title;
  final String status;
  final String? createdAt;
  final int? totalCostCents;
  final int? remainingCents;
  final int? amoPartCents;
  final int? amcPartCents;
  final List<PatientTreatmentPlanPhaseDto> phases;

  const PatientTreatmentPlanDto({
    required this.id,
    required this.title,
    required this.status,
    this.createdAt,
    this.totalCostCents,
    this.remainingCents,
    this.amoPartCents,
    this.amcPartCents,
    this.phases = const [],
  });

  /// `GET /v1/treatment-plans` (liste) : ni coûts ni phases.
  factory PatientTreatmentPlanDto.fromSummaryJson(Map<String, dynamic> json) =>
      PatientTreatmentPlanDto(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String?,
      );

  /// `GET /v1/treatment-plans/:id` (détail) : coûts + phases, pas de `created_at`.
  factory PatientTreatmentPlanDto.fromJson(Map<String, dynamic> json) =>
      PatientTreatmentPlanDto(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        totalCostCents: json['total_cost_cents'] as int?,
        remainingCents: json['remaining_cents'] as int?,
        amoPartCents: json['amo_part_cents'] as int?,
        amcPartCents: json['amc_part_cents'] as int?,
        phases: (json['phases'] as List<dynamic>?)
                ?.map((e) => PatientTreatmentPlanPhaseDto.fromJson(
                    e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  PatientTreatmentPlan toDomain() => PatientTreatmentPlan(
        id: id,
        title: title,
        status: status,
        createdAt: createdAt != null ? DateTime.parse(createdAt!) : null,
        totalCostCents: totalCostCents,
        remainingCents: remainingCents,
        amoPartCents: amoPartCents,
        amcPartCents: amcPartCents,
        phases: phases.map((p) => p.toDomain()).toList(),
      );
}
