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
  final SaveNoteUseCase _saveNote;

  ConsultationCliniqueBloc({
    required GetSessionUseCase getSession,
    required AddActUseCase addAct,
    required CompleteSessionUseCase completeSession,
    required ListClinicalSessionsUseCase listSessions,
    required SaveNoteUseCase saveNote,
  })  : _getSession = getSession,
        _addAct = addAct,
        _completeSession = completeSession,
        _listSessions = listSessions,
        _saveNote = saveNote,
        super(const ConsultationCliniqueInitial()) {
    on<ConsultationCliniqueLoadRequested>(_onLoad);
    on<ConsultationCliniqueActAddRequested>(_onActAdd);
    on<ConsultationCliniqueCompleteRequested>(_onComplete);
    on<ConsultationCliniqueNoteSaveRequested>(_onNoteSave);
    on<ConsultationHistoriqueRequested>(_onHistoriqueLoad);
    on<ConsultationCliniqueActionErrorConsumed>((event, emit) {
      final current = state;
      if (current is ConsultationCliniqueLoaded) {
        emit(current.copyWith(clearActionError: true));
      }
    });
    on<ConsultationCliniqueClinicalRiskWarningConsumed>((event, emit) {
      final current = state;
      if (current is ConsultationCliniqueLoaded) {
        emit(current.copyWith(clearClinicalRiskWarning: true));
      }
    });
    on<ConsultationCliniqueToothSelected>((event, emit) {
      final current = state;
      if (current is ConsultationCliniqueLoaded) {
        emit(current.copyWith(selectedTooth: event.tooth));
      }
    });
    on<ConsultationCliniqueToothCleared>((event, emit) {
      final current = state;
      if (current is ConsultationCliniqueLoaded) {
        emit(current.copyWith(clearSelectedTooth: true));
      }
    });
    on<ConsultationCliniqueToothActConsumed>((event, emit) {
      final current = state;
      if (current is ConsultationCliniqueLoaded) {
        emit(current.copyWith(clearLastAddedToothAct: true));
      }
    });
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
        // #4057/#4058 — alerte clinique bloquante : dialogue dédié, pas un
        // snackbar (l'acte n'a pas été enregistré).
        (failure) async => safeEmit(
          failure is ClinicalRiskWarningFailure
              ? current.copyWith(
                  actionInProgress: false,
                  clinicalRiskWarning: failure.message,
                )
              // #3403 — surface l'erreur (ex. 403 sur séance d'un confrère)
              // au lieu d'un échec silencieux : on porte le message pour le
              // snackbar.
              : current.copyWith(
                  actionInProgress: false,
                  actionError: failure.message,
                ),
        ),
        // #3401 — recharge la séance après un ajout réussi pour rafraîchir la
        // liste des actes et le total (sinon l'écran reste « 0 acte · 0.00 € »).
        // La sélection de dent est consommée par l'acte ; si l'acte portait
        // une dent, on l'expose pour que le module dentaire PROPOSE la mise à
        // jour de l'odontogramme (jamais d'écriture automatique — non-DM).
        (_) async {
          final tooth = event.tooth;
          final addedToothAct = tooth == null || tooth.isEmpty
              ? null
              : AddedToothAct(
                  ccamCode: event.ccamCode,
                  label: event.label,
                  tooth: tooth,
                );
          final reload = await _getSession(current.session.id);
          reload.fold(
            (_) => safeEmit(current.copyWith(
              actionInProgress: false,
              clearSelectedTooth: true,
              lastAddedToothAct: addedToothAct,
            )),
            (s) => safeEmit(ConsultationCliniqueLoaded(
              session: s,
              lastAddedToothAct: addedToothAct,
            )),
          );
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(actionInProgress: false));
    }
  }

  Future<void> _onNoteSave(
    ConsultationCliniqueNoteSaveRequested event,
    Emitter<ConsultationCliniqueState> emit,
  ) async {
    final current = state;
    if (current is! ConsultationCliniqueLoaded) return;
    emit(current.copyWith(actionInProgress: true));
    try {
      final result = await _saveNote(
        consultationId: current.session.id,
        note: event.note,
      );
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
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
