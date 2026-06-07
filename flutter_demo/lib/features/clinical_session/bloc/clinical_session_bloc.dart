import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/clinical_session_repository.dart';
import '../models/clinical_session.dart';
import 'clinical_session_event.dart';
import 'clinical_session_state.dart';

class ClinicalSessionBloc
    extends Bloc<ClinicalSessionEvent, ClinicalSessionState> {
  ClinicalSessionBloc({required ClinicalSessionRepository repository})
      : _repository = repository,
        super(const ClinicalSessionInitial()) {
    on<SessionStartRequested>(_onStartRequested);
    on<SessionActAdded>(_onActAdded);
    on<SessionActRemoved>(_onActRemoved);
    on<SessionCompleteRequested>(_onCompleteRequested);
  }

  final ClinicalSessionRepository _repository;

  Future<void> _onStartRequested(
    SessionStartRequested event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    emit(const ClinicalSessionLoading());
    try {
      final session = await _repository.start(event.appointmentId);
      emit(ClinicalSessionActive(session));
    } catch (e) {
      emit(ClinicalSessionError(e.toString()));
    }
  }

  Future<void> _onActAdded(
    SessionActAdded event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = _currentSession;
    if (current == null) return;
    emit(ClinicalSessionActBusy(current));
    try {
      final updated = await _repository.addAct(
        consultationId: event.consultationId,
        ccamCode: event.ccamCode,
        label: event.label,
        tooth: event.tooth,
        amountCents: event.amountCents,
        included: event.included,
      );
      emit(ClinicalSessionActive(updated));
    } catch (e) {
      emit(ClinicalSessionError(e.toString()));
    }
  }

  Future<void> _onActRemoved(
    SessionActRemoved event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = _currentSession;
    if (current == null) return;
    emit(ClinicalSessionActBusy(current));
    try {
      final updated = await _repository.removeAct(
        consultationId: event.consultationId,
        actId: event.actId,
      );
      emit(ClinicalSessionActive(updated));
    } catch (e) {
      emit(ClinicalSessionError(e.toString()));
    }
  }

  Future<void> _onCompleteRequested(
    SessionCompleteRequested event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = _currentSession;
    if (current == null) return;
    emit(ClinicalSessionActBusy(current));
    try {
      final updated = await _repository.complete(event.consultationId);
      emit(ClinicalSessionCompleted(updated));
    } catch (e) {
      emit(ClinicalSessionError(e.toString()));
    }
  }

  ClinicalSession? get _currentSession => switch (state) {
        ClinicalSessionActive(:final session) => session,
        ClinicalSessionActBusy(:final session) => session,
        _ => null,
      };
}
