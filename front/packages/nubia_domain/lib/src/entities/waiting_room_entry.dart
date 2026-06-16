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

  const WaitingRoomEntry({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    this.appointmentId,
    required this.arrivedAt,
    this.estimatedWaitMinutes,
  });

  Duration get waitSoFar => DateTime.now().difference(arrivedAt);

  @override
  List<Object?> get props => [id];
}
