import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

class ConsultationCliniqueBloc
    extends Bloc<ConsultationCliniqueEvent, ConsultationCliniqueState> {
  final GetSessionUseCase _getSession;
  final AddActUseCase _addAct;
  final CompleteSessionUseCase _completeSession;

  ConsultationCliniqueBloc({
    required GetSessionUseCase getSession,
    required AddActUseCase addAct,
    required CompleteSessionUseCase completeSession,
  })  : _getSession = getSession,
        _addAct = addAct,
        _completeSession = completeSession,
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
        (failure) => emit(ConsultationCliniqueError(failure.message)),
        (session) => emit(ConsultationCliniqueLoaded(session: session)),
      );
    } catch (_) {
      emit(const ConsultationCliniqueError('Erreur de chargement.'));
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
        (failure) async => emit(current.copyWith(actionInProgress: false)),
        (_) async {
          final reload = await _getSession(current.session.id);
          reload.fold(
            (_) => emit(current.copyWith(actionInProgress: false)),
            (s) => emit(ConsultationCliniqueLoaded(session: s)),
          );
        },
      );
    } catch (_) {
      emit(current.copyWith(actionInProgress: false));
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
        (failure) => emit(ConsultationCliniqueError(failure.message)),
        (completed) => emit(ConsultationCliniqueCompleted(completed)),
      );
    } catch (_) {
      emit(ConsultationCliniqueError('Erreur lors de la clôture.'));
    }
  }

  Future<void> _onHistoriqueLoad(
    ConsultationHistoriqueRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    emit(const ConsultationHistoriqueLoaded(sessions: []));
  }
}
