import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'mes_rdv_event.dart';
import 'mes_rdv_state.dart';

class MesRdvBloc extends Bloc<MesRdvEvent, MesRdvState> {
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
    on<MesRdvCancelRequested>(_onCancel);
    on<MesRdvCheckinRequested>(_onCheckin);
  }

  Future<void> _onLoad(
    MesRdvLoadRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    emit(const MesRdvLoading());
    final upcomingResult = await _getUpcoming();
    if (upcomingResult.isLeft()) {
      final message = upcomingResult.fold((f) => f.message, (_) => '');
      emit(MesRdvError(message));
      return;
    }
    final historyResult = await _getHistory();
    historyResult.fold(
      (failure) => emit(MesRdvError(failure.message)),
      (history) => emit(MesRdvLoaded(
        upcoming: upcomingResult.getOrElse(() => []),
        history: history,
      )),
    );
  }

  Future<void> _onCancel(
    MesRdvCancelRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _cancel(event.appointment);
    await result.fold(
      (failure) async => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) async => _onLoad(const MesRdvLoadRequested(), emit),
    );
  }

  Future<void> _onCheckin(
    MesRdvCheckinRequested event,
    Emitter<MesRdvState> emit,
  ) async {
    final current = state;
    if (current is! MesRdvLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _checkin(event.appointmentId);
    await result.fold(
      (failure) async => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) async => _onLoad(const MesRdvLoadRequested(), emit),
    );
  }
}
