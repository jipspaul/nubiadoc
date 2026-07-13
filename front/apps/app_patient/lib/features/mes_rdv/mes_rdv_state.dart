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

  const MesRdvLoaded({
    required this.upcoming,
    required this.history,
    this.actionInProgress = false,
    this.actionError,
    this.historyLoading = false,
    this.historyLoaded = false,
    this.historyError,
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
      ];
}

class MesRdvError extends MesRdvState {
  final String message;
  const MesRdvError(this.message);

  @override
  List<Object?> get props => [message];
}
