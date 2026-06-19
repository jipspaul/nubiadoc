import 'package:nubia_domain/src/entities/appointment.dart';

class AppointmentDto {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final String practitionerSpecialty;
  final String startsAt;
  final int durationMinutes;
  final String motif;
  final String status;
  final String type;
  final String? cabinetAddress;
  final String? cabinetPhone;

  const AppointmentDto({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.practitionerSpecialty,
    required this.startsAt,
    required this.durationMinutes,
    required this.motif,
    required this.status,
    required this.type,
    this.cabinetAddress,
    this.cabinetPhone,
  });

  factory AppointmentDto.fromJson(Map<String, dynamic> json) => AppointmentDto(
        id: json['id'] as String,
        cabinetId: json['cabinet_id'] as String,
        practitionerName: json['practitioner_name'] as String,
        practitionerSpecialty: json['practitioner_specialty'] as String,
        startsAt: json['starts_at'] as String,
        durationMinutes: (json['duration_minutes'] as num).toInt(),
        motif: json['motif'] as String,
        status: json['status'] as String,
        type: json['type'] as String? ?? 'in_person',
        cabinetAddress: json['cabinet_address'] as String?,
        cabinetPhone: json['cabinet_phone'] as String?,
      );

  Appointment toDomain() => Appointment(
        id: id,
        cabinetId: cabinetId,
        practitionerName: practitionerName,
        practitionerSpecialty: practitionerSpecialty,
        startsAt: DateTime.parse(startsAt),
        duration: Duration(minutes: durationMinutes),
        motif: motif,
        status: _parseStatus(status),
        type: type == 'teleconsult'
            ? AppointmentType.teleconsult
            : AppointmentType.inPerson,
        cabinetAddress: cabinetAddress,
        cabinetPhone: cabinetPhone,
      );

  static AppointmentStatus _parseStatus(String value) {
    switch (value) {
      case 'requested':
        return AppointmentStatus.requested;
      case 'confirmed':
        return AppointmentStatus.confirmed;
      case 'cancelled':
        return AppointmentStatus.cancelled;
      case 'completed':
        return AppointmentStatus.completed;
      case 'no_show':
        return AppointmentStatus.noShow;
      default:
        return AppointmentStatus.requested;
    }
  }
}
