import 'package:equatable/equatable.dart';

abstract class WaitingRoomEvent {
  const WaitingRoomEvent();
}

class WaitingRoomLoadRequested extends WaitingRoomEvent {
  const WaitingRoomLoadRequested();
}

class WaitingRoomCallNextRequested extends WaitingRoomEvent {
  const WaitingRoomCallNextRequested();
}

/// Appel d'une entrée précise, hors tête de file (#5166 — bouton « Appeler »
/// par ligne, dérogation manuelle à l'ordre). `CallNextUseCase` n'expose
/// aujourd'hui que l'appel de la tête de file côté back
/// (`POST /cabinet/waiting-room/call-next`) : un endpoint ciblant une entrée
/// précise reste à créer côté back avant de pouvoir traiter cet événement.
class WaitingRoomCallRequested extends WaitingRoomEvent with EquatableMixin {
  const WaitingRoomCallRequested(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}

/// Prévenir le praticien d'une entrée qui dépasse le seuil critique (#6696)
/// — CTA du bandeau d'escalade (#5170).
class WaitingRoomNotifyPractitionerRequested extends WaitingRoomEvent
    with EquatableMixin {
  const WaitingRoomNotifyPractitionerRequested(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}
