import 'package:equatable/equatable.dart';

/// Slot dans l'agenda cabinet.
/// Source : GET /v1/cabinet/agenda
class AgendaEntry extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerId;
  final String practitionerName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? patientId;
  final String? patientName;
  final String? motif;
  final bool isFree;

  const AgendaEntry({
    required this.id,
    required this.cabinetId,
    required this.practitionerId,
    required this.practitionerName,
    required this.startsAt,
    required this.endsAt,
    this.patientId,
    this.patientName,
    this.motif,
    required this.isFree,
  });

  Duration get duration => endsAt.difference(startsAt);

  @override
  List<Object?> get props => [id];
}
