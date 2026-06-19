abstract class WaitingRoomEvent {
  const WaitingRoomEvent();
}

class WaitingRoomLoadRequested extends WaitingRoomEvent {
  const WaitingRoomLoadRequested();
}

class WaitingRoomCallNextRequested extends WaitingRoomEvent {
  const WaitingRoomCallNextRequested();
}
