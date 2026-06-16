import 'package:equatable/equatable.dart';

/// Contexte consultation en cours.
/// Source : GET /v1/cabinet/consultations/:id
class ConsultationContext extends Equatable {
  final String id;
  final String cabinetId;
  final String appointmentId;
  final String patientId;
  final String patientName;
  final String practitionerId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? notes;
  final bool isCompleted;

  const ConsultationContext({
    required this.id,
    required this.cabinetId,
    required this.appointmentId,
    required this.patientId,
    required this.patientName,
    required this.practitionerId,
    required this.startedAt,
    this.endedAt,
    this.notes,
    required this.isCompleted,
  });

  @override
  List<Object?> get props => [id, isCompleted];
}
