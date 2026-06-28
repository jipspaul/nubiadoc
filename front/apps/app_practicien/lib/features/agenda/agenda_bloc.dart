import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_event.dart';
import 'agenda_state.dart';

class AgendaBloc extends Bloc<AgendaEvent, AgendaState>
    with SafeEmitMixin<AgendaState> {
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
    on<TogglePastIncluded>(_onTogglePast);
  }

  Future<void> _fetchAndEmit(
    DateTime weekStart,
    Emitter<AgendaState> emit, {
    required bool includePast,
  }) async {
    emit(const AgendaLoading());
    try {
      final result = await _getAgenda(weekStart, includePast: includePast);
      result.fold(
        (failure) => safeEmit(AgendaError(failure.message)),
        (entries) => safeEmit(AgendaLoaded(
          entries: entries,
          weekStart: weekStart,
          includePast: includePast,
        )),
      );
    } catch (_) {
      safeEmit(const AgendaError('Erreur de chargement de l\'agenda.'));
    }
  }

  Future<void> _onLoad(
    AgendaLoadRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final includePast =
        state is AgendaLoaded ? (state as AgendaLoaded).includePast : false;
    await _fetchAndEmit(event.weekStart, emit, includePast: includePast);
  }

  Future<void> _onWeekChanged(
    AgendaWeekChanged event,
    Emitter<AgendaState> emit,
  ) async {
    await _onLoad(AgendaLoadRequested(weekStart: event.weekStart), emit);
  }

  Future<void> _onTogglePast(
    TogglePastIncluded event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    await _fetchAndEmit(
      current.weekStart,
      emit,
      includePast: !current.includePast,
    );
  }

  Future<void> _onConfirm(
    AgendaAppointmentConfirmRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _confirmAppointment(event.appointmentId);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _fetchAndEmit(
          current.weekStart,
          emit,
          includePast: current.includePast,
        ),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onStartConsultation(
    AgendaConsultationStartRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _startConsultation(event.appointmentId);
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) async => _fetchAndEmit(
          current.weekStart,
          emit,
          includePast: current.includePast,
        ),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
