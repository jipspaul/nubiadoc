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

  /// Id de la séance qui vient d'être démarrée — consommé par la page pour
  /// naviguer vers /consultation (#3367), puis remis à null.
  final String? startedConsultationId;

  const AgendaLoaded({
    required this.entries,
    required this.weekStart,
    this.actionInProgress = false,
    this.actionError,
    this.includePast = false,
    this.startedConsultationId,
  });

  AgendaLoaded copyWith({
    List<AgendaEntry>? entries,
    DateTime? weekStart,
    bool? actionInProgress,
    String? actionError,
    bool clearActionError = false,
    bool? includePast,
    String? startedConsultationId,
    bool clearStartedConsultation = false,
  }) =>
      AgendaLoaded(
        entries: entries ?? this.entries,
        weekStart: weekStart ?? this.weekStart,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        includePast: includePast ?? this.includePast,
        startedConsultationId: clearStartedConsultation
            ? null
            : (startedConsultationId ?? this.startedConsultationId),
      );

  @override
  List<Object?> get props => [
        entries,
        weekStart,
        actionInProgress,
        actionError,
        includePast,
        startedConsultationId,
      ];
}

class AgendaError extends AgendaState {
  final String message;
  const AgendaError(this.message);

  @override
  List<Object?> get props => [message];
}
