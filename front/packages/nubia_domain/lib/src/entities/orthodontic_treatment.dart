import 'package:equatable/equatable.dart';

/// Une étape d'un traitement orthodontique (#4135/#4136).
class OrthodonticStep extends Equatable {
  final String id;
  final int stepNumber;
  final String kind;
  final DateTime? deliveredAt;
  final String? conformityNotes;

  const OrthodonticStep({
    required this.id,
    required this.stepNumber,
    required this.kind,
    this.deliveredAt,
    this.conformityNotes,
  });

  @override
  List<Object?> get props => [id];
}

/// Un traitement orthodontique, avec ses étapes triées par `stepNumber`.
/// Source : `GET /v1/cabinet/patients/:id/orthodontics`.
class OrthodonticTreatment extends Equatable {
  final String id;
  final String? treatmentPlanId;
  final String type;
  final int semesterCount;
  final DateTime? startedAt;
  final String status;
  final List<OrthodonticStep> steps;

  const OrthodonticTreatment({
    required this.id,
    this.treatmentPlanId,
    required this.type,
    required this.semesterCount,
    this.startedAt,
    required this.status,
    required this.steps,
  });

  @override
  List<Object?> get props => [id];
}
