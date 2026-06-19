import 'package:nubia_domain/nubia_domain.dart';

abstract class WaitingRoomState {
  const WaitingRoomState();
}

class WaitingRoomInitial extends WaitingRoomState {
  const WaitingRoomInitial();

  @override
  bool operator ==(Object other) => other is WaitingRoomInitial;

  @override
  int get hashCode => runtimeType.hashCode;
}

class WaitingRoomLoading extends WaitingRoomState {
  const WaitingRoomLoading();

  @override
  bool operator ==(Object other) => other is WaitingRoomLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class WaitingRoomLoaded extends WaitingRoomState {
  const WaitingRoomLoaded(this.entries);

  final List<WaitingRoomEntry> entries;

  @override
  bool operator ==(Object other) =>
      other is WaitingRoomLoaded &&
      other.entries.length == entries.length &&
      List.generate(entries.length, (i) => other.entries[i] == entries[i])
          .every((b) => b);

  @override
  int get hashCode => Object.hashAll(entries);
}

class WaitingRoomError extends WaitingRoomState {
  const WaitingRoomError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is WaitingRoomError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
