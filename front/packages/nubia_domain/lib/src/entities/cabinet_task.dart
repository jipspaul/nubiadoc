import 'package:equatable/equatable.dart';

/// Une tâche interne du cabinet (#7211/#7210), éventuellement liée à un
/// patient/RDV — ex. « tâche pour l'assistante » posée depuis un RDV.
/// Source : `GET /v1/cabinet/tasks`.
class CabinetTask extends Equatable {
  final String id;
  final String title;
  final String? description;
  final String? assigneeUserId;
  final String? assigneeDisplayName;
  final String? patientId;
  final String? patientDisplayName;
  final String? appointmentId;
  final String? dueDate;
  final String status;
  final String createdBy;
  final String createdAt;
  final String? doneAt;

  const CabinetTask({
    required this.id,
    required this.title,
    this.description,
    this.assigneeUserId,
    this.assigneeDisplayName,
    this.patientId,
    this.patientDisplayName,
    this.appointmentId,
    this.dueDate,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.doneAt,
  });

  bool get isOpen => status == 'open';
  bool get isDone => status == 'done';

  @override
  List<Object?> get props => [id, status];
}
