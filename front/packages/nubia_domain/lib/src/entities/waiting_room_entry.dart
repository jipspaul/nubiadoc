import 'package:equatable/equatable.dart';

/// Patient en salle d'attente.
/// Source : GET /v1/cabinet/waiting-room
class WaitingRoomEntry extends Equatable {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String? appointmentId;
  final DateTime arrivedAt;
  final int? estimatedWaitMinutes;
  /// `checked_in` (en salle d'attente) ou `in_consultation` (au fauteuil) —
  /// cf. `api/src/scheduling.rs` (#6636 : jamais parsé, pastille figée).
  final String? status;
  /// Motif admin du RDV (ex. "Détartrage") — pas de motif clinique (#5172).
  final String? reason;
  /// Motif du RDV pour anticiper l'acte en un coup d'œil (ex. "Pose de
  /// couronne", "Contrôle annuel") — distinct de [reason] (#5029).
  final String? appointmentReason;
  final DateTime? appointmentTime;
  /// Praticien attendu (#5168) — `null` quand l'urgence n'est pas encore
  /// attribuée (cf. [appointmentId]).
  final String? practitionerId;
  final String? practitionerName;
  /// Heure prévue du RDV (pour calculer le retard sur le planning, #5031).
  final DateTime? scheduledAt;

  const WaitingRoomEntry({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    required this.arrivedAt,
    this.estimatedWaitMinutes,
    this.status,
    this.reason,
    this.appointmentReason,
    this.appointmentTime,
    this.practitionerId,
    this.practitionerName,
    this.scheduledAt,
  });

  Duration get waitSoFar => DateTime.now().difference(arrivedAt);

  @override
  List<Object?> get props => [id];
}
