import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class WaitingRoomState extends Equatable {
  const WaitingRoomState();

  @override
  List<Object?> get props => [];
}

class WaitingRoomInitial extends WaitingRoomState {
  const WaitingRoomInitial();
}

class WaitingRoomLoading extends WaitingRoomState {
  const WaitingRoomLoading();
}

class WaitingRoomLoaded extends WaitingRoomState {
  final List<WaitingRoomEntry> entries;
  final bool actionInProgress;
  final String? actionError;

  const WaitingRoomLoaded({
    required this.entries,
    this.actionInProgress = false,
    this.actionError,
  });

  WaitingRoomLoaded copyWith({
    List<WaitingRoomEntry>? entries,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      WaitingRoomLoaded(
        entries: entries ?? this.entries,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props => [entries, actionInProgress, actionError];
}

class WaitingRoomError extends WaitingRoomState {
  final String message;
  const WaitingRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
