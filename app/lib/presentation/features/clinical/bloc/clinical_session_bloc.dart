import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';
import 'package:nubia_patient/domain/usecases/clinical/add_act_use_case.dart';
import 'package:nubia_patient/domain/usecases/clinical/complete_session_use_case.dart';
import 'package:nubia_patient/domain/usecases/clinical/get_session_use_case.dart';
import 'package:nubia_patient/domain/usecases/clinical/remove_act_use_case.dart';
import 'package:nubia_patient/domain/usecases/clinical/start_session_use_case.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class ClinicalSessionEvent extends Equatable {
  const ClinicalSessionEvent();

  @override
  List<Object?> get props => [];
}

/// Triggered when the practitioner taps "Démarrer la consultation".
class SessionStartRequested extends ClinicalSessionEvent {
  final String appointmentId;

  const SessionStartRequested(this.appointmentId);

  @override
  List<Object?> get props => [appointmentId];
}

/// Triggered to reload session data (e.g. on screen open with existing session).
class SessionLoadRequested extends ClinicalSessionEvent {
  final String consultationId;

  const SessionLoadRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

/// Triggered when the practitioner submits the add-act form.
class SessionActAdded extends ClinicalSessionEvent {
  final String consultationId;
  final String ccamCode;
  final String label;
  final String? tooth;
  final int? amountCents;
  final bool included;

  const SessionActAdded({
    required this.consultationId,
    required this.ccamCode,
    required this.label,
    this.tooth,
    this.amountCents,
    this.included = false,
  });

  @override
  List<Object?> get props => [
        consultationId,
        ccamCode,
        label,
        tooth,
        amountCents,
        included,
      ];
}

/// Triggered when the practitioner swipes/deletes an act.
class SessionActRemoved extends ClinicalSessionEvent {
  final String consultationId;
  final String actId;

  const SessionActRemoved({
    required this.consultationId,
    required this.actId,
  });

  @override
  List<Object?> get props => [consultationId, actId];
}

/// Triggered when the practitioner taps "Terminer & facturer".
class SessionCompleteRequested extends ClinicalSessionEvent {
  final String consultationId;

  const SessionCompleteRequested(this.consultationId);

  @override
  List<Object?> get props => [consultationId];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class ClinicalSessionState extends Equatable {
  const ClinicalSessionState();

  @override
  List<Object?> get props => [];
}

class ClinicalSessionInitial extends ClinicalSessionState {
  const ClinicalSessionInitial();
}

class ClinicalSessionLoading extends ClinicalSessionState {
  const ClinicalSessionLoading();
}

/// Session loaded and active.
class ClinicalSessionLoaded extends ClinicalSessionState {
  final ClinicalSession session;

  /// True while an act is being added or removed (inline loading).
  final bool actLoading;

  const ClinicalSessionLoaded({
    required this.session,
    this.actLoading = false,
  });

  ClinicalSessionLoaded copyWith({
    ClinicalSession? session,
    bool? actLoading,
  }) =>
      ClinicalSessionLoaded(
        session: session ?? this.session,
        actLoading: actLoading ?? this.actLoading,
      );

  @override
  List<Object?> get props => [session, actLoading];
}

/// Session successfully completed.
class ClinicalSessionCompleted extends ClinicalSessionState {
  final SessionCompleteResult result;

  const ClinicalSessionCompleted(this.result);

  @override
  List<Object?> get props => [result];
}

class ClinicalSessionError extends ClinicalSessionState {
  final String message;

  const ClinicalSessionError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class ClinicalSessionBloc
    extends Bloc<ClinicalSessionEvent, ClinicalSessionState> {
  final StartSessionUseCase _startSession;
  final GetSessionUseCase _getSession;
  final AddActUseCase _addAct;
  final RemoveActUseCase _removeAct;
  final CompleteSessionUseCase _completeSession;

  ClinicalSessionBloc(
    this._startSession,
    this._getSession,
    this._addAct,
    this._removeAct,
    this._completeSession,
  ) : super(const ClinicalSessionInitial()) {
    on<SessionStartRequested>(_onStartRequested);
    on<SessionLoadRequested>(_onLoadRequested);
    on<SessionActAdded>(_onActAdded);
    on<SessionActRemoved>(_onActRemoved);
    on<SessionCompleteRequested>(_onCompleteRequested);
  }

  Future<void> _onStartRequested(
    SessionStartRequested event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    emit(const ClinicalSessionLoading());
    final result = await _startSession(event.appointmentId);
    result.fold(
      (failure) => emit(ClinicalSessionError(failure.message)),
      (session) => emit(ClinicalSessionLoaded(session: session)),
    );
  }

  Future<void> _onLoadRequested(
    SessionLoadRequested event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    emit(const ClinicalSessionLoading());
    final result = await _getSession(event.consultationId);
    result.fold(
      (failure) => emit(ClinicalSessionError(failure.message)),
      (session) => emit(ClinicalSessionLoaded(session: session)),
    );
  }

  Future<void> _onActAdded(
    SessionActAdded event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = state;
    if (current is! ClinicalSessionLoaded) return;

    emit(current.copyWith(actLoading: true));

    final result = await _addAct(
      consultationId: event.consultationId,
      ccamCode: event.ccamCode,
      label: event.label,
      tooth: event.tooth,
      amountCents: event.amountCents,
      included: event.included,
    );
    result.fold(
      (failure) => emit(ClinicalSessionError(failure.message)),
      (act) {
        final updatedActs = [...current.session.acts, act];
        emit(
          current.copyWith(
            session: ClinicalSession(
              id: current.session.id,
              appointmentId: current.session.appointmentId,
              status: current.session.status,
              acts: updatedActs,
            ),
            actLoading: false,
          ),
        );
      },
    );
  }

  Future<void> _onActRemoved(
    SessionActRemoved event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = state;
    if (current is! ClinicalSessionLoaded) return;

    emit(current.copyWith(actLoading: true));

    final result = await _removeAct(
      consultationId: event.consultationId,
      actId: event.actId,
    );
    result.fold(
      (failure) => emit(ClinicalSessionError(failure.message)),
      (_) {
        final updatedActs = current.session.acts
            .where((a) => a.id != event.actId)
            .toList();
        emit(
          current.copyWith(
            session: ClinicalSession(
              id: current.session.id,
              appointmentId: current.session.appointmentId,
              status: current.session.status,
              acts: updatedActs,
            ),
            actLoading: false,
          ),
        );
      },
    );
  }

  Future<void> _onCompleteRequested(
    SessionCompleteRequested event,
    Emitter<ClinicalSessionState> emit,
  ) async {
    final current = state;
    if (current is! ClinicalSessionLoaded) return;

    emit(current.copyWith(actLoading: true));

    final result = await _completeSession(event.consultationId);
    result.fold(
      (failure) => emit(ClinicalSessionError(failure.message)),
      (completionResult) => emit(ClinicalSessionCompleted(completionResult)),
    );
  }
}
