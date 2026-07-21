import 'package:nubia_domain/src/entities/treatment_plan.dart';

class TreatmentPhaseDto {
  final String id;
  final int position;
  final String title;
  final String status;

  const TreatmentPhaseDto({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
  });

  factory TreatmentPhaseDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPhaseDto(
        id: json['id'] as String,
        position: json['position'] as int,
        title: json['title'] as String,
        status: json['status'] as String,
      );

  TreatmentPhase toDomain() => TreatmentPhase(
        id: id,
        position: position,
        title: title,
        status: status,
      );
}

class TreatmentPlanDto {
  final String id;
  final String title;
  final String status;
  final String createdAt;
  final List<TreatmentPhaseDto> phases;

  const TreatmentPlanDto({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.phases,
  });

  factory TreatmentPlanDto.fromJson(Map<String, dynamic> json) =>
      TreatmentPlanDto(
        id: json['id'] as String,
        title: json['title'] as String,
        status: json['status'] as String,
        createdAt: json['created_at'] as String,
        phases: (json['phases'] as List<dynamic>? ?? const [])
            .map((p) => TreatmentPhaseDto.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  TreatmentPlan toDomain() => TreatmentPlan(
        id: id,
        title: title,
        status: status,
        createdAt: DateTime.parse(createdAt),
        phases: phases.map((p) => p.toDomain()).toList(),
      );
}
