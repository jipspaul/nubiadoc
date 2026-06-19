import 'package:nubia_domain/src/entities/cabinet_appointment.dart';

class CabinetAppointmentDto {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String practitionerId;
  final String practitionerName;
  final String startsAt;
  final int durationMinutes;
  final String motif;
  final String status;

  const CabinetAppointmentDto({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.practitionerId,
    required this.practitionerName,
    required this.startsAt,
    required this.durationMinutes,
    required this.motif,
    required this.status,
  });

  factory CabinetAppointmentDto.fromJson(Map<String, dynamic> json) =>
      CabinetAppointmentDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        patientId: json['patient_id'] as String,
        patientName: json['patient_name'] as String,
        practitionerId: json['practitioner_id'] as String,
        practitionerName: json['practitioner_name'] as String,
        startsAt: json['starts_at'] as String,
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        motif: json['motif'] as String,
        status: json['status'] as String,
      );

  Map<String, dynamic> toJson() => {
        'patient_id': patientId,
        'practitioner_id': practitionerId,
        'starts_at': startsAt,
        'duration_minutes': durationMinutes,
        'motif': motif,
        'status': status,
      };

  CabinetAppointment toDomain() => CabinetAppointment(
        id: id,
        cabinetId: cabinetId,
        patientId: patientId,
        patientName: patientName,
        practitionerId: practitionerId,
        practitionerName: practitionerName,
        startsAt: DateTime.parse(startsAt),
        duration: Duration(minutes: durationMinutes),
        motif: motif,
        status: _parseStatus(status),
      );

  static CabinetAppointmentStatus _parseStatus(String value) {
    switch (value) {
      case 'requested':
        return CabinetAppointmentStatus.requested;
      case 'confirmed':
        return CabinetAppointmentStatus.confirmed;
      case 'in_progress':
        return CabinetAppointmentStatus.inProgress;
      case 'completed':
        return CabinetAppointmentStatus.completed;
      case 'cancelled':
        return CabinetAppointmentStatus.cancelled;
      case 'no_show':
        return CabinetAppointmentStatus.noShow;
      default:
        return CabinetAppointmentStatus.requested;
    }
  }
}
