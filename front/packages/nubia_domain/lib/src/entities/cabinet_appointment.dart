import 'package:equatable/equatable.dart';

enum CabinetAppointmentStatus {
  requested,
  confirmed,
  inProgress,
  completed,
  cancelled,
  noShow,
}

/// RDV vu côté cabinet (avec status, patient_id).
/// Source : GET /v1/cabinet/appointments
class CabinetAppointment extends Equatable {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String practitionerId;
  final String practitionerName;
  final DateTime startsAt;
  final Duration duration;
  final String motif;
  final CabinetAppointmentStatus status;

  const CabinetAppointment({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.practitionerId,
    required this.practitionerName,
    required this.startsAt,
    required this.duration,
    required this.motif,
    required this.status,
  });

  bool get isConfirmed => status == CabinetAppointmentStatus.confirmed;
  bool get canCancel =>
      status == CabinetAppointmentStatus.requested ||
      status == CabinetAppointmentStatus.confirmed;

  @override
  List<Object?> get props => [id, status];
}
