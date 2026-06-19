import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_event.dart';
import 'consultation_state.dart';

class ConsultationBloc extends Bloc<ConsultationEvent, ConsultationState> {
  final GetSessionUseCase _getSession;
  final AddActUseCase _addAct;
  final RemoveActUseCase _removeAct;
  final CompleteSessionUseCase _completeSession;

  ConsultationBloc({
    required GetSessionUseCase getSession,
    required AddActUseCase addAct,
    required RemoveActUseCase removeAct,
    required CompleteSessionUseCase completeSession,
  })  : _getSession = getSession,
        _addAct = addAct,
        _removeAct = removeAct,
        _completeSession = completeSession,
        super(const ConsultationInitial()) {
    on<ConsultationLoadRequested>(_onLoad);
    on<ConsultationActAddRequested>(_onActAdd);
    on<ConsultationActRemoveRequested>(_onActRemove);
    on<ConsultationCompleteRequested>(_onComplete);
  }

  Future<void> _onLoad(
    ConsultationLoadRequested event,
    Emitter<ConsultationState> emit,
  ) async {
    emit(const ConsultationLoading());
    final result = await _getSession(event.consultationId);
    result.fold(
      (failure) => emit(ConsultationError(failure.message)),
      (session) => emit(ConsultationLoaded(session: session)),
    );
  }

  Future<void> _onActAdd(
    ConsultationActAddRequested event,
    Emitter<ConsultationState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _addAct(
      consultationId: event.consultationId,
      ccamCode: event.ccamCode,
      label: event.label,
      tooth: event.tooth,
      amountCents: event.amountCents,
      included: event.included,
    );
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(ConsultationLoadRequested(event.consultationId)),
    );
  }

  Future<void> _onActRemove(
    ConsultationActRemoveRequested event,
    Emitter<ConsultationState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _removeAct(
      consultationId: event.consultationId,
      actId: event.actId,
    );
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) => add(ConsultationLoadRequested(event.consultationId)),
    );
  }

  Future<void> _onComplete(
    ConsultationCompleteRequested event,
    Emitter<ConsultationState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _completeSession(event.consultationId);
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (completeResult) => emit(ConsultationCompleted(completeResult)),
    );
  }
}
