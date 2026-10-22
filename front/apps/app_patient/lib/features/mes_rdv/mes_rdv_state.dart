import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class MesRdvState extends Equatable {
  const MesRdvState();

  @override
  List<Object?> get props => [];
}

class MesRdvInitial extends MesRdvState {
  const MesRdvInitial();
}

class MesRdvLoading extends MesRdvState {
  const MesRdvLoading();
}

class MesRdvLoaded extends MesRdvState {
  final List<Appointment> upcoming;
  final List<Appointment> history;
  final bool actionInProgress;
  final String? actionError;
  final bool historyLoading;
  final bool historyLoaded;
  final String? historyError;

  /// `true` tant qu'une page d'historique suivante reste à charger
  /// (`page.next_cursor` non nul à la dernière page récupérée) — #8365 :
  /// l'historique se charge page par page à la demande (défilement) plutôt
  /// qu'en une seule pagination exhaustive avant le premier rendu.
  final bool historyHasMore;

  /// Chargement de la page d'historique suivante en cours (défilement) —
  /// affiche un indicateur en pied de liste plutôt qu'un rechargement
  /// complet.
  final bool historyLoadingMore;

  const MesRdvLoaded({
    required this.upcoming,
    required this.history,
    this.actionInProgress = false,
    this.actionError,
    this.historyLoading = false,
    this.historyLoaded = false,
    this.historyError,
    this.historyHasMore = false,
    this.historyLoadingMore = false,
  });

  MesRdvLoaded copyWith({
    List<Appointment>? upcoming,
    List<Appointment>? history,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    bool? historyLoading,
    bool? historyLoaded,
    String? historyError,
    bool clearHistoryError = false,
    bool? historyHasMore,
    bool? historyLoadingMore,
  }) =>
      MesRdvLoaded(
        upcoming: upcoming ?? this.upcoming,
        history: history ?? this.history,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        historyLoading: historyLoading ?? this.historyLoading,
        historyLoaded: historyLoaded ?? this.historyLoaded,
        historyError:
            clearHistoryError ? null : (historyError ?? this.historyError),
        historyHasMore: historyHasMore ?? this.historyHasMore,
        historyLoadingMore: historyLoadingMore ?? this.historyLoadingMore,
      );

  @override
  List<Object?> get props => [
        upcoming,
        history,
        actionInProgress,
        actionError,
        historyLoading,
        historyLoaded,
        historyError,
        historyHasMore,
        historyLoadingMore,
      ];
}

class MesRdvError extends MesRdvState {
  final String message;
  const MesRdvError(this.message);

  @override
  List<Object?> get props => [message];
}
