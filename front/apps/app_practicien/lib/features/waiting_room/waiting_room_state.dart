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

  /// Erreur d'un rechargement (action ou refresh périodique) survenu alors
  /// qu'une liste était déjà affichée : non bloquante, affichée via
  /// `NubiaInlineError` (le plein écran `WaitingRoomError` reste réservé au
  /// chargement initial).
  final String? reloadError;

  const WaitingRoomLoaded({
    required this.entries,
    this.actionInProgress = false,
    this.actionError,
    this.reloadError,
  });

  WaitingRoomLoaded copyWith({
    List<WaitingRoomEntry>? entries,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    String? reloadError,
    bool clearReloadError = false,
  }) =>
      WaitingRoomLoaded(
        entries: entries ?? this.entries,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        reloadError:
            clearReloadError ? null : (reloadError ?? this.reloadError),
      );

  @override
  List<Object?> get props =>
      [entries, actionInProgress, actionError, reloadError];
}

class WaitingRoomError extends WaitingRoomState {
  final String message;
  const WaitingRoomError(this.message);

  @override
  List<Object?> get props => [message];
}
