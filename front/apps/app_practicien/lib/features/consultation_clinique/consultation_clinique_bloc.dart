import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'consultation_clinique_event.dart';
import 'consultation_clinique_state.dart';

class ConsultationCliniqueBloc
    extends Bloc<ConsultationCliniqueEvent, ConsultationCliniqueState> {
  ConsultationCliniqueBloc({
    required GetSessionUseCase getSession,
    required AddActUseCase addAct,
    required CompleteSessionUseCase completeSession,
  })  : _getSession = getSession,
        _addAct = addAct,
        _completeSession = completeSession,
        super(const ConsultationCliniqueInitial()) {
    on<ConsultationCliniqueLoadRequested>(_onLoad);
    on<ConsultationCliniqueActAdded>(_onActAdded);
    on<ConsultationCliniqueCompleted>(_onCompleted);
  }

  final GetSessionUseCase _getSession;
  final AddActUseCase _addAct;
  final CompleteSessionUseCase _completeSession;
  String? _consultationId;

  Future<void> _onLoad(
    ConsultationCliniqueLoadRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    emit(const ConsultationCliniqueLoading());
    _consultationId = event.consultationId;
    final result = await _getSession(event.consultationId);
    result.fold(
      (failure) => emit(ConsultationCliniqueError(failure.message)),
      (session) => emit(ConsultationCliniqueLoaded(session: session)),
    );
  }

  Future<void> _onActAdded(
    ConsultationCliniqueActAdded event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationCliniqueLoaded || _consultationId == null) {
      return;
    }
    emit(ConsultationCliniqueLoaded(
      session: current.session,
      actionInProgress: true,
    ));
    final result = await _addAct(
      consultationId: _consultationId!,
      ccamCode: event.ccamCode,
      label: event.label,
      tooth: event.tooth,
      amountCents: event.amountCents,
    );
    result.fold(
      (failure) => emit(ConsultationCliniqueLoaded(
        session: current.session,
        actionError: failure.message,
      )),
      (act) => emit(ConsultationCliniqueLoaded(
        session: ClinicalSession(
          id: current.session.id,
          appointmentId: current.session.appointmentId,
          status: current.session.status,
          acts: [...current.session.acts, act],
        ),
      )),
    );
  }

  Future<void> _onCompleted(
    ConsultationCliniqueCompleted event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationCliniqueLoaded || _consultationId == null) {
      return;
    }
    final result = await _completeSession(_consultationId!);
    result.fold(
      (failure) => emit(ConsultationCliniqueLoaded(
        session: current.session,
        actionError: failure.message,
      )),
      (res) => emit(
        ConsultationCliniqueCompleteSuccess(invoiceId: res.invoiceId),
      ),
    );
  }
}
