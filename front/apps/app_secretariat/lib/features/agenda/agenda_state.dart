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
  final List<Slot> availableSlots;
  final bool actionInProgress;
  final String? actionError;

  const AgendaLoaded({
    required this.entries,
    this.availableSlots = const [],
    this.actionInProgress = false,
    this.actionError,
  });

  AgendaLoaded copyWith({
    List<AgendaEntry>? entries,
    List<Slot>? availableSlots,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
  }) =>
      AgendaLoaded(
        entries: entries ?? this.entries,
        availableSlots: availableSlots ?? this.availableSlots,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
      );

  @override
  List<Object?> get props =>
      [entries, availableSlots, actionInProgress, actionError];
}

class AgendaError extends AgendaState {
  final String message;
  const AgendaError(this.message);

  @override
  List<Object?> get props => [message];
}
