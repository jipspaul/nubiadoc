import 'package:equatable/equatable.dart';

enum AppointmentStatus { requested, confirmed, cancelled, completed, noShow }
enum AppointmentType { inPerson, teleconsult }

class Appointment extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final String practitionerSpecialty;
  final DateTime startsAt;
  final Duration duration;
  final String motif;
  final AppointmentStatus status;
  final AppointmentType type;
  final String? cabinetAddress;
  final String? cabinetPhone;

  const Appointment({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.practitionerSpecialty,
    required this.startsAt,
    required this.duration,
    required this.motif,
    required this.status,
    this.type = AppointmentType.inPerson,
    this.cabinetAddress,
    this.cabinetPhone,
  });

  bool get isUpcoming => startsAt.isAfter(DateTime.now()) && status == AppointmentStatus.confirmed;
  bool get canCancel => isUpcoming;
  bool get canModify => isUpcoming;

  @override
  List<Object?> get props => [id, status, startsAt];
}
