import 'package:equatable/equatable.dart';

/// Créneau bookable dans l'agenda d'un praticien.
/// Source : GET /v1/cabinet/slots
class Slot extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerId;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isAvailable;

  const Slot({
    required this.id,
    required this.cabinetId,
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
    required this.isAvailable,
  });

  Duration get duration => endsAt.difference(startsAt);

  @override
  List<Object?> get props => [id, isAvailable];
}
