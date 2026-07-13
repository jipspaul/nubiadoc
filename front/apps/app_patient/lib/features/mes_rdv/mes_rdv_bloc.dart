import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_rdv_event.dart';
import 'mes_rdv_state.dart';

class MesRdvBloc extends Bloc<MesRdvEvent, MesRdvState>
    with SafeEmitMixin<MesRdvState> {
  final GetUpcomingAppointmentsUseCase _getUpcoming;
  final GetAppointmentHistoryUseCase _getHistory;
  final CancelAppointmentUseCase _cancel;
  final CheckinAppointmentUseCase _checkin;

  MesRdvBloc({
    required GetUpcomingAppointmentsUseCase getUpcoming,
    required GetAppointmentHistoryUseCase getHistory,
    required CancelAppointmentUseCase cancel,
    required CheckinAppointmentUseCase checkin,
  })  : _getUpcoming = getUpcoming,
        _getHistory = getHistory,
        _cancel = cancel,
        _checkin = checkin,
        super(const MesRdvInitial()) {
    on<MesRdvLoadRequested>(_onLoad);
    on<MesRdvHistoryRequested>(_onHistoryLoad);
    on<MesRdvCancelRequested>(_onCancel);
    on<MesRdvCheckinRequested>(_onCheckin);
  }

  Future<void> _onLoad(
    MesRdvLoadRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    emit(const MesRdvLoading());
    try {
      final upcomingResult = await _getUpcoming();
      upcomingResult.fold(
        (failure) => safeEmit(MesRdvError(failure.message)),
        // La vue À venir s'affiche dès sa réponse ; l'historique se charge
        // paresseusement (voir _onHistoryLoad), sans bloquer ce rendu.
        (upcoming) => safeEmit(MesRdvLoaded(upcoming: upcoming, history: const [])),
      );
    } catch (_) {
      safeEmit(const MesRdvError('Erreur de chargement.'));
    }
  }

  Future<void> _onHistoryLoad(
    MesRdvHistoryRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    if (current.historyLoading || current.historyLoaded) return;
    safeEmit(current.copyWith(historyLoading: true, clearHistoryError: true));
    try {
      final historyResult = await _getHistory();
      historyResult.fold(
        (failure) => safeEmit(current.copyWith(
          historyLoading: false,
          historyError: failure.message,
        )),
        (history) => safeEmit(current.copyWith(
          history: history,
          historyLoading: false,
          historyLoaded: true,
        )),
      );
    } catch (_) {
      safeEmit(current.copyWith(
        historyLoading: false,
        historyError: 'Erreur de chargement.',
      ));
    }
  }

  Future<void> _onCancel(
    MesRdvCancelRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _cancel(event.appointment);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _onLoad(const MesRdvLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onCheckin(
    MesRdvCheckinRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _checkin(event.appointmentId);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _onLoad(const MesRdvLoadRequested(), emit),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
