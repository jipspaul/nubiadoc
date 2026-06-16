import 'package:equatable/equatable.dart';

/// Patient en liste d'attente (pas encore de créneau confirmé).
/// Source : GET /v1/cabinet/waiting-list
class WaitingListEntry extends Equatable {
  final String id;
  final String cabinetId;
  final String patientId;
  final String patientName;
  final String motif;
  final DateTime requestedAt;
  final int position;

  const WaitingListEntry({
    required this.id,
    required this.cabinetId,
    required this.patientId,
    required this.patientName,
    required this.motif,
    required this.requestedAt,
    required this.position,
  });

  @override
  List<Object?> get props => [id, position];
}
