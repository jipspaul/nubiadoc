import 'package:equatable/equatable.dart';

abstract class WaitingRoomEvent extends Equatable {
  const WaitingRoomEvent();

  @override
  List<Object?> get props => [];
}

class WaitingRoomLoadRequested extends WaitingRoomEvent {
  const WaitingRoomLoadRequested();
}

class WaitingRoomCallNextRequested extends WaitingRoomEvent {
  const WaitingRoomCallNextRequested();
}

/// Appel d'une entrée précise, hors tête de file (bouton « Appeler » par
/// ligne, #5033/#5166 côté secrétariat). `CallNextUseCase` n'expose
/// aujourd'hui que l'appel de la tête de file côté back
/// (`POST /cabinet/waiting-room/call-next`) : un endpoint ciblant une entrée
/// précise reste à créer côté back avant de pouvoir traiter cet événement
/// pour une entrée qui n'est pas déjà en tête de file.
class WaitingRoomCallRequested extends WaitingRoomEvent {
  const WaitingRoomCallRequested(this.entryId);

  final String entryId;

  @override
  List<Object?> get props => [entryId];
}
