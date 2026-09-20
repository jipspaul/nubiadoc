import 'package:equatable/equatable.dart';

/// Séance d'un plan de traitement (#7172, DP-F16.c) — répartition des actes
/// proposée par `POST .../sessions/propose` (#7173, algorithme documenté
/// côté API). `status` vaut `planned` tant qu'aucun créneau n'a été
/// réservé, `scheduled` une fois [appointmentId] renseigné.
class TreatmentSession extends Equatable {
  final String id;
  final int position;
  final int durationMin;
  final List<String> quoteItemIds;
  final String status;
  final String? appointmentId;

  const TreatmentSession({
    required this.id,
    required this.position,
    required this.durationMin,
    required this.quoteItemIds,
    this.status = 'planned',
    this.appointmentId,
  });

  TreatmentSession copyWith({
    int? position,
    String? status,
    String? appointmentId,
  }) =>
      TreatmentSession(
        id: id,
        position: position ?? this.position,
        durationMin: durationMin,
        quoteItemIds: quoteItemIds,
        status: status ?? this.status,
        appointmentId: appointmentId ?? this.appointmentId,
      );

  @override
  List<Object?> get props =>
      [id, position, durationMin, quoteItemIds, status, appointmentId];
}

/// Créneau proposé pour une séance (`POST .../sessions/:id/slots`, #7173).
class ProposedSlot extends Equatable {
  final String id;
  final String practitionerId;
  final DateTime startsAt;
  final DateTime endsAt;

  const ProposedSlot({
    required this.id,
    required this.practitionerId,
    required this.startsAt,
    required this.endsAt,
  });

  @override
  List<Object?> get props => [id, practitionerId, startsAt, endsAt];
}
