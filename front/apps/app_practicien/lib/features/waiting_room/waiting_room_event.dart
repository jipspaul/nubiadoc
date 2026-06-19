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
