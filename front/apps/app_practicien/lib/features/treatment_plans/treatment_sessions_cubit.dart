//! Cubit de la section « Séances » d'un plan de traitement (#7172,
//! DP-F16.c).
//!
//! Quoi : propose une répartition en séances (`propose`, #7173 — persistée
//! côté API dès l'appel, un `propose` répété ajoute de nouvelles séances aux
//! actes pas encore affectés plutôt que de tout redécouper), permet de les
//! réordonner localement (`reorder` — aucun endpoint de persistance de
//! l'ordre n'existe côté API, réordonnancement visuel seulement), affiche
//! les créneaux proposés pour une séance (`loadSlots`) et réserve un
//! créneau (`schedule`, crée le RDV lié).
//!
//! État : [TreatmentSessionsInitial] tant qu'aucune séance n'a été proposée
//! NI relue ; [TreatmentSessionsLoaded] ensuite — y compris dès la création
//! du cubit si `initialSessions` (séances déjà persistées, portées par
//! `TreatmentPlan.sessions`, #7477) n'est pas vide, sans quoi les séances
//! d'un plan rechargé devenaient irrécupérables. `actionError` porté par
//! l'état en cas d'échec d'une action, séances déjà affichées conservées —
//! même convention que `TreatmentPlansCubit`.

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

sealed class TreatmentSessionsState extends Equatable {
  const TreatmentSessionsState();

  @override
  List<Object?> get props => [];
}

class TreatmentSessionsInitial extends TreatmentSessionsState {
  const TreatmentSessionsInitial();
}

class TreatmentSessionsLoaded extends TreatmentSessionsState {
  const TreatmentSessionsLoaded({
    required this.sessions,
    this.busy = false,
    this.actionError,
    this.expandedSessionId,
    this.slots = const [],
    this.slotsLoading = false,
  });

  final List<TreatmentSession> sessions;
  final bool busy;
  final String? actionError;
  final String? expandedSessionId;
  final List<ProposedSlot> slots;
  final bool slotsLoading;

  TreatmentSessionsLoaded copyWith({
    List<TreatmentSession>? sessions,
    bool? busy,
    String? actionError,
    bool clearActionError = false,
    String? expandedSessionId,
    bool clearExpandedSessionId = false,
    List<ProposedSlot>? slots,
    bool? slotsLoading,
  }) =>
      TreatmentSessionsLoaded(
        sessions: sessions ?? this.sessions,
        busy: busy ?? this.busy,
        actionError:
            clearActionError ? null : (actionError ?? this.actionError),
        expandedSessionId: clearExpandedSessionId
            ? null
            : (expandedSessionId ?? this.expandedSessionId),
        slots: slots ?? this.slots,
        slotsLoading: slotsLoading ?? this.slotsLoading,
      );

  @override
  List<Object?> get props =>
      [sessions, busy, actionError, expandedSessionId, slots, slotsLoading];
}

class TreatmentSessionsCubit extends Cubit<TreatmentSessionsState> {
  TreatmentSessionsCubit({
    required this.planId,
    List<TreatmentSession> initialSessions = const [],
    required ProposeTreatmentSessionsUseCase proposeSessions,
    required ProposeSessionSlotsUseCase proposeSlots,
    required ScheduleTreatmentSessionUseCase scheduleSession,
  })  : _propose = proposeSessions,
        _slots = proposeSlots,
        _schedule = scheduleSession,
        super(
          initialSessions.isEmpty
              ? const TreatmentSessionsInitial()
              : TreatmentSessionsLoaded(sessions: initialSessions),
        );

  final String planId;
  final ProposeTreatmentSessionsUseCase _propose;
  final ProposeSessionSlotsUseCase _slots;
  final ScheduleTreatmentSessionUseCase _schedule;

  List<TreatmentSession> get _currentSessions {
    final current = state;
    return current is TreatmentSessionsLoaded ? current.sessions : const [];
  }

  Future<void> propose({int? defaultDurationMin}) async {
    final existing = _currentSessions;
    emit(TreatmentSessionsLoaded(sessions: existing, busy: true));
    final result =
        await _propose(planId, defaultDurationMin: defaultDurationMin);
    result.fold(
      (failure) => emit(TreatmentSessionsLoaded(
        sessions: existing,
        actionError: failure.message,
      )),
      (proposed) => emit(
        TreatmentSessionsLoaded(sessions: [...existing, ...proposed]),
      ),
    );
  }

  /// Réordonnancement local uniquement (glisser-déposer) — aucun endpoint
  /// ne persiste l'ordre des séances côté API à ce jour.
  void reorder(int oldIndex, int newIndex) {
    final current = state;
    if (current is! TreatmentSessionsLoaded) return;
    final sessions = List<TreatmentSession>.from(current.sessions);
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = sessions.removeAt(oldIndex);
    sessions.insert(newIndex, moved);
    final renumbered = [
      for (final entry in sessions.indexed)
        entry.$2.copyWith(position: entry.$1 + 1),
    ];
    emit(current.copyWith(sessions: renumbered));
  }

  Future<void> loadSlots(String sessionId) async {
    final current = state;
    if (current is! TreatmentSessionsLoaded) return;
    emit(current.copyWith(
      expandedSessionId: sessionId,
      slotsLoading: true,
      slots: const [],
      clearActionError: true,
    ));
    final result = await _slots(planId, sessionId);
    result.fold(
      (failure) => emit(current.copyWith(
        expandedSessionId: sessionId,
        slotsLoading: false,
        actionError: failure.message,
      )),
      (slots) => emit(current.copyWith(
        expandedSessionId: sessionId,
        slotsLoading: false,
        slots: slots,
      )),
    );
  }

  void collapseSlots() {
    final current = state;
    if (current is! TreatmentSessionsLoaded) return;
    emit(current.copyWith(clearExpandedSessionId: true, slots: const []));
  }

  Future<void> schedule(String sessionId, String slotId) async {
    final current = state;
    if (current is! TreatmentSessionsLoaded) return;
    emit(current.copyWith(busy: true, clearActionError: true));
    final result = await _schedule(planId, sessionId, slotId);
    await result.fold(
      (failure) async =>
          emit(current.copyWith(busy: false, actionError: failure.message)),
      (appointmentId) async => emit(TreatmentSessionsLoaded(
        sessions: [
          for (final session in current.sessions)
            if (session.id == sessionId)
              session.copyWith(
                status: 'scheduled',
                appointmentId: appointmentId,
              )
            else
              session,
        ],
      )),
    );
  }
}
