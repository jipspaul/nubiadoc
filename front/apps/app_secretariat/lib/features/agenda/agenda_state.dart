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

  /// Roster praticien_id -> nom, résolu via `ListCabinetPractitionersUseCase`
  /// (même source que le picker « Nouveau RDV », #4608). Contrairement à une
  /// map construite depuis `entries`, ce roster reste complet même quand la
  /// semaine affichée ne contient aucun créneau/RDV pour un praticien donné.
  final Map<String, String> practitionerNames;

  /// Lundi de la semaine actuellement affichée (#5082 — nécessaire pour que
  /// la navigation clavier ←/→/T calcule la semaine suivante/précédente à
  /// partir de la semaine réellement affichée, pas de « aujourd'hui »).
  final DateTime weekStart;

  const AgendaLoaded({
    required this.entries,
    required this.weekStart,
    this.availableSlots = const [],
    this.actionInProgress = false,
    this.actionError,
    this.practitionerNames = const {},
  });

  AgendaLoaded copyWith({
    List<AgendaEntry>? entries,
    List<Slot>? availableSlots,
    bool? actionInProgress,
    String? actionError,
    Map<String, String>? practitionerNames,
    DateTime? weekStart,
    bool clearActionError = false,
  }) =>
      AgendaLoaded(
        entries: entries ?? this.entries,
        availableSlots: availableSlots ?? this.availableSlots,
        actionInProgress: actionInProgress ?? this.actionInProgress,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        practitionerNames: practitionerNames ?? this.practitionerNames,
        weekStart: weekStart ?? this.weekStart,
      );

  @override
  List<Object?> get props => [
        entries,
        availableSlots,
        actionInProgress,
        actionError,
        practitionerNames,
        weekStart,
      ];
}

class AgendaError extends AgendaState {
  final String message;
  const AgendaError(this.message);

  @override
  List<Object?> get props => [message];
}
