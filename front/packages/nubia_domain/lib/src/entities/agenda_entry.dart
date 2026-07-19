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

  /// Statut administratif du RDV renvoyé par le back (`requested`, `confirmed`,
  /// `in_progress`, `completed`, `cancelled`, `no_show`…). Champ NON clinique,
  /// nécessaire pour afficher le bon libellé (« À confirmer » / « Confirmé »)
  /// et masquer le bouton « Confirmer » une fois le RDV confirmé. Vide pour un
  /// créneau libre.
  final String status;

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
    this.status = '',
  });

  Duration get duration => endsAt.difference(startsAt);

  /// Le RDV est confirmé (le secrétaire n'a plus à agir).
  bool get isConfirmed => status == 'confirmed';

  /// Le RDV attend une confirmation du secrétariat.
  bool get isPending => status == 'requested';

  /// Le patient est arrivé (check-in effectué), consultation pas encore démarrée.
  bool get isCheckedIn => status == 'checked_in';

  /// La consultation est en cours.
  bool get isInProgress => status == 'in_progress';

  /// Le RDV est terminé.
  bool get isDone => status == 'done';

  /// Le RDV a été annulé.
  bool get isCancelled => status == 'cancelled';

  /// Le patient ne s'est pas présenté.
  bool get isNoShow => status == 'no_show';

  @override
  List<Object?> get props => [id, status];
}
