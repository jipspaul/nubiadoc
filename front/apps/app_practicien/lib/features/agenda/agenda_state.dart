import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class AgendaState extends Equatable {
  const AgendaState();

  @override
  List<Object?> get props => [];
}

class AgendaInitial extends AgendaState {
  const AgendaInitial();
}

class AgendaLoading extends AgendaState {
  const AgendaLoading();
}

class AgendaLoaded extends AgendaState {
  final List<AgendaEntry> entries;
  final DateTime weekStart;
  final bool actionInProgress;
  final String? actionError;
  final bool includePast;

  const AgendaLoaded({
    required this.entries,
    required this.weekStart,
    this.actionInProgress = false,
    this.actionError,
    this.includePast = false,
  });

  AgendaLoaded copyWith({
    List<AgendaEntry>? entries,
    DateTime? weekStart,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    bool? includePast,
  }) =>
      AgendaLoaded(
        entries: entries ?? this.entries,
        weekStart: weekStart ?? this.weekStart,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        includePast: includePast ?? this.includePast,
      );

  @override
  List<Object?> get props =>
      [entries, weekStart, actionInProgress, actionError, includePast];
}

class AgendaError extends AgendaState {
  final String message;
  const AgendaError(this.message);

  @override
  List<Object?> get props => [message];
}
