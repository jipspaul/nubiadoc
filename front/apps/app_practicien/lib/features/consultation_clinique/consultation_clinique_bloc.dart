import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

class ConsultationCliniqueBloc
    extends Bloc<ConsultationCliniqueEvent, ConsultationCliniqueState>
    with SafeEmitMixin<ConsultationCliniqueState> {
  final GetSessionUseCase _getSession;
  final AddActUseCase _addAct;
  final CompleteSessionUseCase _completeSession;
  final ListClinicalSessionsUseCase _listSessions;

  ConsultationCliniqueBloc({
    required GetSessionUseCase getSession,
    required AddActUseCase addAct,
    required CompleteSessionUseCase completeSession,
    required ListClinicalSessionsUseCase listSessions,
  })  : _getSession = getSession,
        _addAct = addAct,
        _completeSession = completeSession,
        _listSessions = listSessions,
        super(const ConsultationCliniqueInitial()) {
    on<ConsultationCliniqueLoadRequested>(_onLoad);
    on<ConsultationCliniqueActAddRequested>(_onActAdd);
    on<ConsultationCliniqueCompleteRequested>(_onComplete);
    on<ConsultationHistoriqueRequested>(_onHistoriqueLoad);
  }

  Future<void> _onLoad(
    ConsultationCliniqueLoadRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    emit(const ConsultationCliniqueLoading());
    try {
      final result = await _getSession(event.consultationId);
      result.fold(
        (failure) => safeEmit(ConsultationCliniqueError(failure.message)),
        (session) => safeEmit(ConsultationCliniqueLoaded(session: session)),
      );
    } catch (_) {
      safeEmit(const ConsultationCliniqueError('Erreur de chargement.'));
    }
  }

  Future<void> _onActAdd(
    ConsultationCliniqueActAddRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationCliniqueLoaded) return;
    emit(current.copyWith(actionInProgress: true));
    try {
      final result = await _addAct(
        consultationId: current.session.id,
        ccamCode: event.ccamCode,
        label: event.label,
        tooth: event.tooth,
        amountCents: event.amountCents,
        included: event.included,
      );
      await result.fold(
        (failure) async => safeEmit(current.copyWith(actionInProgress: false)),
        (_) async {
          final reload = await _getSession(current.session.id);
          reload.fold(
            (_) => safeEmit(current.copyWith(actionInProgress: false)),
            (s) => safeEmit(ConsultationCliniqueLoaded(session: s)),
          );
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(actionInProgress: false));
    }
  }

  Future<void> _onComplete(
    ConsultationCliniqueCompleteRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationCliniqueLoaded) return;
    emit(current.copyWith(actionInProgress: true));
    try {
      final result = await _completeSession(current.session.id);
      result.fold(
        (failure) => safeEmit(ConsultationCliniqueError(failure.message)),
        (completed) => safeEmit(ConsultationCliniqueCompleted(completed)),
      );
    } catch (_) {
      safeEmit(ConsultationCliniqueError('Erreur lors de la clôture.'));
    }
  }

  Future<void> _onHistoriqueLoad(
    ConsultationHistoriqueRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    emit(const ConsultationCliniqueLoading());
    try {
      final result = await _listSessions();
      result.fold(
        (failure) => safeEmit(ConsultationCliniqueError(failure.message)),
        (sessions) =>
            safeEmit(ConsultationHistoriqueLoaded(sessions: sessions)),
      );
    } catch (_) {
      safeEmit(const ConsultationCliniqueError(
          "Erreur de chargement de l'historique."));
    }
  }
}
