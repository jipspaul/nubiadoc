import 'package:nubia_domain/src/entities/orthodontic_treatment.dart';

class OrthodonticStepDto {
  final String id;
  final int stepNumber;
  final String kind;
  final String? deliveredAt;
  final String? conformityNotes;

  const OrthodonticStepDto({
    required this.id,
    required this.stepNumber,
    required this.kind,
    this.deliveredAt,
    this.conformityNotes,
  });

  factory OrthodonticStepDto.fromJson(Map<String, dynamic> json) =>
      OrthodonticStepDto(
        id: json['id'] as String,
        stepNumber: json['step_number'] as int,
        kind: json['kind'] as String,
        deliveredAt: json['delivered_at'] as String?,
        conformityNotes: json['conformity_notes'] as String?,
      );

  OrthodonticStep toDomain() => OrthodonticStep(
        id: id,
        stepNumber: stepNumber,
        kind: kind,
        deliveredAt: deliveredAt == null ? null : DateTime.parse(deliveredAt!),
        conformityNotes: conformityNotes,
      );
}

class OrthodonticTreatmentDto {
  final String id;
  final String? treatmentPlanId;
  final String type;
  final int semesterCount;
  final String? startedAt;
  final String status;
  final List<OrthodonticStepDto> steps;

  const OrthodonticTreatmentDto({
    required this.id,
    this.treatmentPlanId,
    required this.type,
    required this.semesterCount,
    this.startedAt,
    required this.status,
    required this.steps,
  });

  factory OrthodonticTreatmentDto.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'] as List<dynamic>? ?? [];
    return OrthodonticTreatmentDto(
      id: json['id'] as String,
      treatmentPlanId: json['treatment_plan_id'] as String?,
      type: json['type'] as String,
      semesterCount: json['semester_count'] as int,
      startedAt: json['started_at'] as String?,
      status: json['status'] as String,
      steps: rawSteps
          .map((e) => OrthodonticStepDto.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  OrthodonticTreatment toDomain() => OrthodonticTreatment(
        id: id,
        treatmentPlanId: treatmentPlanId,
        type: type,
        semesterCount: semesterCount,
        startedAt: startedAt == null ? null : DateTime.parse(startedAt!),
        status: status,
        steps: steps.map((s) => s.toDomain()).toList(),
      );
}
