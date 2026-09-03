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
  final CreateAppointmentSeriesUseCase _createAppointmentSeries;

  /// Id du praticien connecté (cf. `AuthSession.practitionerId`) — restreint
  /// systématiquement l'agenda chargé à ses propres RDV (#6213 : sans ce
  /// filtre, un praticien voyait la journée complète du cabinet, RDV d'un
  /// confrère inclus, sous un titre « Ma journée »).
  final String? _practitionerId;

  AgendaBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required ConfirmAppointmentUseCase confirmAppointment,
    required StartConsultationUseCase startConsultation,
    required CreateAppointmentSeriesUseCase createAppointmentSeries,
    String? practitionerId,
  })  : _getAgenda = getAgenda,
        _confirmAppointment = confirmAppointment,
        _startConsultation = startConsultation,
        _createAppointmentSeries = createAppointmentSeries,
        _practitionerId = practitionerId,
        super(const AgendaInitial()) {
    on<AgendaLoadRequested>(_onLoad);
    on<AgendaWeekChanged>(_onWeekChanged);
    on<AgendaAppointmentConfirmRequested>(_onConfirm);
    on<AgendaConsultationStartRequested>(_onStartConsultation);
    on<AgendaStartedConsultationConsumed>((event, emit) {
      final current = state;
      if (current is AgendaLoaded) {
        emit(current.copyWith(clearStartedConsultation: true));
      }
    });
    on<TogglePastIncluded>(_onTogglePast);
    on<AgendaSeriesCreateRequested>(_onCreateSeries);
    on<AgendaSeriesCreatedConsumed>((event, emit) {
      final current = state;
      if (current is AgendaLoaded) {
        emit(current.copyWith(clearSeriesAppointmentsCreated: true));
      }
    });
  }

  Future<void> _fetchAndEmit(
    DateTime weekStart,
    Emitter<AgendaState> emit, {
    required bool includePast,
    String? startedConsultationId,
    int? seriesAppointmentsCreated,
  }) async {
    emit(const AgendaLoading());
    try {
      final result = await _getAgenda(
        weekStart,
        includePast: includePast,
        practitionerId: _practitionerId,
      );
      result.fold(
        (failure) => safeEmit(AgendaError(failure.message)),
        (entries) => safeEmit(AgendaLoaded(
          entries: entries,
          weekStart: weekStart,
          includePast: includePast,
          startedConsultationId: startedConsultationId,
          seriesAppointmentsCreated: seriesAppointmentsCreated,
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
        // La session démarrée est propagée au state : la page navigue vers
        // /consultation?id=… (#3367 — le clic « Démarrer » ne faisait rien
        // de visible).
        (session) async => _fetchAndEmit(
          current.weekStart,
          emit,
          includePast: current.includePast,
          startedConsultationId: session.id,
        ),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onCreateSeries(
    AgendaSeriesCreateRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _createAppointmentSeries(
        practitionerId: event.practitionerId,
        patientId: event.patientId,
        motif: event.motif,
        occurrences: event.occurrences,
      );
      await result.fold(
        (failure) async => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (series) async => _fetchAndEmit(
          current.weekStart,
          emit,
          includePast: current.includePast,
          seriesAppointmentsCreated: series.appointments.length,
        ),
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
