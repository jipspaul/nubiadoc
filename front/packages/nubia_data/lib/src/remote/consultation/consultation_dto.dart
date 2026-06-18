import 'package:nubia_domain/src/entities/consultation_context.dart';

class ConsultationContextDto {
  final String id;
  final String cabinetId;
  final String appointmentId;
  final String patientId;
  final String patientName;
  final String practitionerId;
  final String startedAt;
  final String? endedAt;
  final String? notes;
  final bool isCompleted;

  const ConsultationContextDto({
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

  factory ConsultationContextDto.fromJson(Map<String, dynamic> json) =>
      ConsultationContextDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        appointmentId: json['appointment_id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        practitionerId: json['practitioner_id'] as String,
        startedAt: json['started_at'] as String,
        endedAt: json['ended_at'] as String?,
        notes: json['notes'] as String?,
        isCompleted: (json['is_completed'] as bool?) ?? false,
      );

  Map<String, dynamic> toJson() => {
        'appointment_id': appointmentId,
        if (notes != null) 'notes': notes,
        'is_completed': isCompleted,
      };

  ConsultationContext toDomain() => ConsultationContext(
        id: id,
        cabinetId: cabinetId,
        appointmentId: appointmentId,
        patientId: patientId,
        patientName: patientName,
        practitionerId: practitionerId,
        startedAt: DateTime.parse(startedAt),
        endedAt: endedAt != null ? DateTime.parse(endedAt!) : null,
        notes: notes,
        isCompleted: isCompleted,
      );
}
