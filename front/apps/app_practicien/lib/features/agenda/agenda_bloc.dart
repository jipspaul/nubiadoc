import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_event.dart';
import 'agenda_state.dart';

class AgendaBloc extends Bloc<AgendaEvent, AgendaState> {
  final GetCabinetAgendaUseCase _getAgenda;
  final ConfirmAppointmentUseCase _confirmAppointment;
  final StartConsultationUseCase _startConsultation;

  AgendaBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required ConfirmAppointmentUseCase confirmAppointment,
    required StartConsultationUseCase startConsultation,
  })  : _getAgenda = getAgenda,
        _confirmAppointment = confirmAppointment,
        _startConsultation = startConsultation,
        super(const AgendaInitial()) {
    on<AgendaLoadRequested>(_onLoad);
    on<AgendaWeekChanged>(_onWeekChanged);
    on<AgendaAppointmentConfirmRequested>(_onConfirm);
    on<AgendaConsultationStartRequested>(_onStartConsultation);
  }

  Future<void> _onLoad(
    AgendaLoadRequested event,
    Emitter<AgendaState> emit,
  ) async {
    emit(const AgendaLoading());
    final result = await _getAgenda(event.weekStart);
    result.fold(
      (failure) => emit(AgendaError(failure.message)),
      (entries) => emit(AgendaLoaded(entries: entries, weekStart: event.weekStart)),
    );
  }

  Future<void> _onWeekChanged(
    AgendaWeekChanged event,
    Emitter<AgendaState> emit,
  ) async {
    await _onLoad(AgendaLoadRequested(weekStart: event.weekStart), emit);
  }

  Future<void> _onConfirm(
    AgendaAppointmentConfirmRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _confirmAppointment(event.appointmentId);
    await result.fold(
      (failure) async => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) async =>
          _onLoad(AgendaLoadRequested(weekStart: current.weekStart), emit),
    );
  }

  Future<void> _onStartConsultation(
    AgendaConsultationStartRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _startConsultation(event.appointmentId);
    await result.fold(
      (failure) async => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) async =>
          _onLoad(AgendaLoadRequested(weekStart: current.weekStart), emit),
    );
  }
}
