import 'package:equatable/equatable.dart';

/// Statut d'un rendez-vous patient (GET /v1/appointments).
enum AppointmentStatus {
  requested,
  confirmed,
  cancelled,
  done,
}

/// Rendez-vous patient — contrat GET /v1/appointments & /v1/appointments/{id}.
class Appointment extends Equatable {
  const Appointment({
    required this.id,
    required this.providerName,
    required this.motif,
    required this.startsAt,
    required this.status,
    this.address,
  });

  final String id;
  final String providerName;
  final String motif;
  final DateTime startsAt;
  final AppointmentStatus status;

  /// Adresse du cabinet — disponible dans le détail.
  final String? address;

  @override
  List<Object?> get props => [id, providerName, motif, startsAt, status, address];
}
