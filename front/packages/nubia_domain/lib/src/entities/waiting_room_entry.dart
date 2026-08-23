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
  /// Motif admin du RDV (ex. "Détartrage") — pas de motif clinique (#5172).
  final String? reason;
  final DateTime? appointmentTime;

  const WaitingRoomEntry({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    required this.arrivedAt,
    this.estimatedWaitMinutes,
    this.reason,
    this.appointmentTime,
  });

  Duration get waitSoFar => DateTime.now().difference(arrivedAt);

  @override
  List<Object?> get props => [id];
}
