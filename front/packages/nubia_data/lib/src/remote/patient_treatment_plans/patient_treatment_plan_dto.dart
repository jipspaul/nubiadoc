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
  final String? description;
  final String? pendingQuoteId;
  final String? pendingQuoteSentAt;
  final String? appointmentId;
  final String? appointmentAt;

  const PatientTreatmentPlanPhaseDto({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.items = const [],
    this.description,
    this.pendingQuoteId,
    this.pendingQuoteSentAt,
    this.appointmentId,
    this.appointmentAt,
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
        description: json['description'] as String?,
        pendingQuoteId: json['pending_quote_id'] as String?,
        pendingQuoteSentAt: json['pending_quote_sent_at'] as String?,
        appointmentId: json['appointment_id'] as String?,
        appointmentAt: json['appointment_at'] as String?,
      );

  PatientTreatmentPlanPhase toDomain() => PatientTreatmentPlanPhase(
        id: id,
        position: position,
        title: title,
        status: status,
        items: items.map((i) => i.toDomain()).toList(),
        description: description,
        pendingQuoteId: pendingQuoteId,
        pendingQuoteSentAt: pendingQuoteSentAt != null
            ? DateTime.parse(pendingQuoteSentAt!)
            : null,
        appointmentId: appointmentId,
        appointmentAt:
            appointmentAt != null ? DateTime.parse(appointmentAt!) : null,
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
  final String? pendingQuoteId;
  final String? pendingQuoteLabel;
  final String? pendingQuoteReceivedAt;
  final int? pendingQuotePatientShareCents;
  final String? nextAppointmentId;
  final String? nextAppointmentAt;
  final String? practitionerName;
  final String? proposedAt;
  final int? currentStep;
  final int? stepCount;
  final String? currentPhaseTitle;

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
    this.pendingQuoteId,
    this.pendingQuoteLabel,
    this.pendingQuoteReceivedAt,
    this.pendingQuotePatientShareCents,
    this.nextAppointmentId,
    this.nextAppointmentAt,
    this.practitionerName,
    this.proposedAt,
    this.currentStep,
    this.stepCount,
    this.currentPhaseTitle,
  });

  /// `GET /v1/treatment-plans` (liste) : `total_cost_cents` (#6242) mais pas
  /// de détail (`remaining_cents`/`amo_part_cents`/`amc_part_cents`/phases).
  factory PatientTreatmentPlanDto.fromSummaryJson(Map<String, dynamic> json) =>
      PatientTreatmentPlanDto(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String?,
        totalCostCents: json['total_cost_cents'] as int?,
        pendingQuoteId: json['pending_quote_id'] as String?,
        pendingQuoteLabel: json['pending_quote_label'] as String?,
        pendingQuoteReceivedAt: json['pending_quote_received_at'] as String?,
        pendingQuotePatientShareCents:
            json['pending_quote_patient_share_cents'] as int?,
        nextAppointmentId: json['next_appointment_id'] as String?,
        nextAppointmentAt: json['next_appointment_at'] as String?,
        practitionerName: json['practitioner_name'] as String?,
        proposedAt: json['proposed_at'] as String?,
        currentStep: json['current_step'] as int?,
        stepCount: json['step_count'] as int?,
        currentPhaseTitle: json['current_phase_title'] as String?,
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
        pendingQuoteId: json['pending_quote_id'] as String?,
        pendingQuoteLabel: json['pending_quote_label'] as String?,
        pendingQuoteReceivedAt: json['pending_quote_received_at'] as String?,
        pendingQuotePatientShareCents:
            json['pending_quote_patient_share_cents'] as int?,
        nextAppointmentId: json['next_appointment_id'] as String?,
        nextAppointmentAt: json['next_appointment_at'] as String?,
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
        pendingQuoteId: pendingQuoteId,
        pendingQuoteLabel: pendingQuoteLabel,
        pendingQuoteReceivedAt: pendingQuoteReceivedAt != null
            ? DateTime.parse(pendingQuoteReceivedAt!)
            : null,
        pendingQuotePatientShareCents: pendingQuotePatientShareCents,
        nextAppointmentId: nextAppointmentId,
        nextAppointmentAt:
            nextAppointmentAt != null ? DateTime.parse(nextAppointmentAt!) : null,
        practitionerName: practitionerName,
        proposedAt: proposedAt != null ? DateTime.parse(proposedAt!) : null,
        currentStep: currentStep,
        stepCount: stepCount,
        currentPhaseTitle: currentPhaseTitle,
      );
}
