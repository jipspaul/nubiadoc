import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_event.dart';
import 'agenda_state.dart';

class AgendaBloc extends Bloc<AgendaEvent, AgendaState> {
  final GetCabinetAgendaUseCase _getAgenda;
  final CreateCabinetAppointmentUseCase _createAppointment;
  final ConfirmAppointmentUseCase _confirmAppointment;
  final RescheduleAppointmentUseCase _rescheduleAppointment;
  final ListBookableSlotsUseCase _listSlots;

  DateTime? _currentWeekStart;

  AgendaBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required CreateCabinetAppointmentUseCase createAppointment,
    required ConfirmAppointmentUseCase confirmAppointment,
    required RescheduleAppointmentUseCase rescheduleAppointment,
    required ListBookableSlotsUseCase listSlots,
  })  : _getAgenda = getAgenda,
        _createAppointment = createAppointment,
        _confirmAppointment = confirmAppointment,
        _rescheduleAppointment = rescheduleAppointment,
        _listSlots = listSlots,
        super(const AgendaInitial()) {
    on<AgendaLoadRequested>(_onLoad);
    on<AgendaAppointmentCreateRequested>(_onCreate);
    on<AgendaAppointmentConfirmRequested>(_onConfirm);
    on<AgendaAppointmentRescheduleRequested>(_onReschedule);
  }

  Future<void> _onLoad(
    AgendaLoadRequested event,
    Emitter<AgendaState> emit,
  ) async {
    _currentWeekStart = event.weekStart;
    emit(const AgendaLoading());
    final entriesResult = await _getAgenda(event.weekStart);
    if (entriesResult.isLeft()) {
      final failure = entriesResult.fold((f) => f, (_) => null)!;
      emit(AgendaError(failure.message));
      return;
    }
    final slotsResult = await _listSlots();
    final entries = entriesResult.getOrElse(() => []);
    final slots = slotsResult.getOrElse(() => []);
    emit(AgendaLoaded(entries: entries, availableSlots: slots));
  }

  Future<void> _onCreate(
    AgendaAppointmentCreateRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _createAppointment(event.appointment);
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) {
        if (_currentWeekStart != null) {
          add(AgendaLoadRequested(weekStart: _currentWeekStart!));
        }
      },
    );
  }

  Future<void> _onConfirm(
    AgendaAppointmentConfirmRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result = await _confirmAppointment(event.appointmentId);
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) {
        if (_currentWeekStart != null) {
          add(AgendaLoadRequested(weekStart: _currentWeekStart!));
        }
      },
    );
  }

  Future<void> _onReschedule(
    AgendaAppointmentRescheduleRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    final result =
        await _rescheduleAppointment(event.appointmentId, event.newStartsAt);
    result.fold(
      (failure) => emit(current.copyWith(
        actionInProgress: false,
        actionError: failure.message,
      )),
      (_) {
        if (_currentWeekStart != null) {
          add(AgendaLoadRequested(weekStart: _currentWeekStart!));
        }
      },
    );
  }
}
