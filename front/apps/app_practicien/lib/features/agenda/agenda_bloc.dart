import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../session/pro_auth_cubit.dart';
import 'agenda_event.dart';
import 'agenda_state.dart';

/// Rechargement interne déclenché quand [ProAuthCubit] résout l'id du
/// praticien après que ce bloc a déjà été construit (#8681) — jamais émis
/// par l'UI.
class _AgendaPractitionerIdResolved extends AgendaEvent {
  const _AgendaPractitionerIdResolved(this.practitionerId);
  final String practitionerId;

  @override
  List<Object?> get props => [practitionerId];
}

class AgendaBloc extends Bloc<AgendaEvent, AgendaState>
    with SafeEmitMixin<AgendaState> {
  final GetCabinetAgendaUseCase _getAgenda;
  final ConfirmAppointmentUseCase _confirmAppointment;
  final StartConsultationUseCase _startConsultation;
  final CreateAppointmentSeriesUseCase _createAppointmentSeries;
  final CancelCabinetAppointmentUseCase _cancelAppointment;
  final StreamSubscription<AuthState> _authSubscription;

  /// Id du praticien connecté (cf. `AuthSession.practitionerId`) — restreint
  /// systématiquement l'agenda chargé à ses propres RDV (#6213 : sans ce
  /// filtre, un praticien voyait la journée complète du cabinet, RDV d'un
  /// confrère inclus, sous un titre « Ma journée »).
  ///
  /// Mutable (#8681) : au rechargement de page, ce bloc (factory) peut être
  /// construit alors que `ProAuthCubit.restore()` attend encore `GET /v1/me`
  /// — l'id serait alors figé à `null` pour toute la durée de vie du bloc,
  /// et l'agenda resterait non filtré (RDV d'un confrère inclus) jusqu'au
  /// prochain logout/login. On s'abonne au cubit pour rattraper l'id dès
  /// qu'il est résolu et recharger la semaine affichée avec le bon filtre.
  String? _practitionerId;
  DateTime? _lastWeekStart;
  bool _lastIncludePast = false;

  static String? _practitionerIdOf(AuthState state) => switch (state) {
        AuthAuthenticated(:final session) => session.practitionerId,
        _ => null,
      };

  AgendaBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required ConfirmAppointmentUseCase confirmAppointment,
    required StartConsultationUseCase startConsultation,
    required CreateAppointmentSeriesUseCase createAppointmentSeries,
    required CancelCabinetAppointmentUseCase cancelAppointment,
    required ProAuthCubit authCubit,
  })  : _getAgenda = getAgenda,
        _confirmAppointment = confirmAppointment,
        _startConsultation = startConsultation,
        _createAppointmentSeries = createAppointmentSeries,
        _cancelAppointment = cancelAppointment,
        _practitionerId = _practitionerIdOf(authCubit.state),
        _authSubscription = authCubit.stream.listen((_) {}),
        super(const AgendaInitial()) {
    on<AgendaLoadRequested>(_onLoad);
    on<AgendaWeekChanged>(_onWeekChanged);
    on<AgendaAppointmentConfirmRequested>(_onConfirm);
    on<AgendaConsultationStartRequested>(_onStartConsultation);
    on<AgendaAppointmentCancelRequested>(_onCancel);
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
    on<_AgendaPractitionerIdResolved>(_onPractitionerIdResolved);
    // #8681 : seule une résolution vers un id *non null* et différent nous
    // intéresse ici (rattraper le `null` capturé pendant que `restore()`
    // attendait encore `GET /v1/me`) — une transition vers `null`
    // (déconnexion/session expirée) ne doit pas déclencher un rechargement
    // de l'agenda sans filtre, l'écran est de toute façon sur le point
    // d'être quitté par le routeur.
    _authSubscription.onData((authState) {
      final id = _practitionerIdOf(authState);
      if (id != null && id != _practitionerId) {
        add(_AgendaPractitionerIdResolved(id));
      }
    });
  }

  Future<void> _onPractitionerIdResolved(
    _AgendaPractitionerIdResolved event,
    Emitter<AgendaState> emit,
  ) async {
    _practitionerId = event.practitionerId;
    final weekStart = _lastWeekStart;
    if (weekStart == null) return;
    await _fetchAndEmit(weekStart, emit, includePast: _lastIncludePast);
  }

  @override
  Future<void> close() {
    _authSubscription.cancel();
    return super.close();
  }

  Future<void> _fetchAndEmit(
    DateTime weekStart,
    Emitter<AgendaState> emit, {
    required bool includePast,
    String? startedConsultationId,
    int? seriesAppointmentsCreated,
  }) async {
    _lastWeekStart = weekStart;
    _lastIncludePast = includePast;
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

  Future<void> _onCancel(
    AgendaAppointmentCancelRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _cancelAppointment(event.appointmentId);
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
