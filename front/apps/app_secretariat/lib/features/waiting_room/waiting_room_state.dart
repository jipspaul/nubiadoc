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
  WaitingRoomLoaded(
    this.entries, {
    DateTime? loadedAt,
    this.actionInProgress = false,
    this.actionError,
  }) : loadedAt = loadedAt ?? DateTime.now();

  final List<WaitingRoomEntry> entries;

  /// Instant de réception des données affichées — source de l'indicateur
  /// de fraîcheur (« Actualisé il y a N s », #5161).
  final DateTime loadedAt;

  /// Une action (appel suivant/ligne) est en cours côté back.
  final bool actionInProgress;

  /// Échec d'une action (ex. appel suivant) : signalé en ligne, sans
  /// remplacer la liste par un écran plein écran (#5159) — contrairement à
  /// [WaitingRoomError], réservé à l'échec du chargement initial.
  final String? actionError;

  WaitingRoomLoaded copyWith({
    List<WaitingRoomEntry>? entries,
    DateTime? loadedAt,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      WaitingRoomLoaded(
        entries ?? this.entries,
        loadedAt: loadedAt ?? this.loadedAt,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  // loadedAt est un horodatage d'affichage, pas une donnée métier : exclu
  // de l'égalité pour ne pas casser la comparaison entre deux chargements
  // identiques (bloc_test).
  @override
  bool operator ==(Object other) =>
      other is WaitingRoomLoaded &&
      other.entries.length == entries.length &&
      List.generate(entries.length, (i) => other.entries[i] == entries[i])
          .every((b) => b) &&
      other.actionInProgress == actionInProgress &&
      other.actionError == actionError;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(entries), actionInProgress, actionError);
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
