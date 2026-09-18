import 'package:nubia_domain/src/entities/cabinet_task.dart';

class CabinetTaskDto {
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

  const CabinetTaskDto({
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

  factory CabinetTaskDto.fromJson(Map<String, dynamic> json) => CabinetTaskDto(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        assigneeUserId: json['assignee_user_id'] as String?,
        assigneeDisplayName: json['assignee_display_name'] as String?,
        patientId: json['patient_id'] as String?,
        patientDisplayName: json['patient_display_name'] as String?,
        appointmentId: json['appointment_id'] as String?,
        dueDate: json['due_date'] as String?,
        status: json['status'] as String,
        createdBy: json['created_by'] as String,
        createdAt: json['created_at'] as String,
        doneAt: json['done_at'] as String?,
      );

  CabinetTask toDomain() => CabinetTask(
        id: id,
        title: title,
        description: description,
        assigneeUserId: assigneeUserId,
        assigneeDisplayName: assigneeDisplayName,
        patientId: patientId,
        patientDisplayName: patientDisplayName,
        appointmentId: appointmentId,
        dueDate: dueDate,
        status: status,
        createdBy: createdBy,
        createdAt: createdAt,
        doneAt: doneAt,
      );
}
