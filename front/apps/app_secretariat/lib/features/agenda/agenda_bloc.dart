import 'package:bloc/bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'agenda_event.dart';
import 'agenda_state.dart';

class AgendaBloc extends Bloc<AgendaEvent, AgendaState>
    with SafeEmitMixin<AgendaState> {
  final GetCabinetAgendaUseCase _getAgenda;
  final CreateCabinetAppointmentUseCase _createAppointment;
  final ConfirmAppointmentUseCase _confirmAppointment;
  final CabinetCheckinAppointmentUseCase _checkinAppointment;
  final RescheduleAppointmentUseCase _rescheduleAppointment;
  final ListBookableSlotsUseCase _listSlots;
  final ListCabinetPractitionersUseCase _listPractitioners;

  DateTime? _currentWeekStart;

  AgendaBloc({
    required GetCabinetAgendaUseCase getAgenda,
    required CreateCabinetAppointmentUseCase createAppointment,
    required ConfirmAppointmentUseCase confirmAppointment,
    required CabinetCheckinAppointmentUseCase checkinAppointment,
    required RescheduleAppointmentUseCase rescheduleAppointment,
    required ListBookableSlotsUseCase listSlots,
    required ListCabinetPractitionersUseCase listPractitioners,
  })  : _getAgenda = getAgenda,
        _createAppointment = createAppointment,
        _confirmAppointment = confirmAppointment,
        _checkinAppointment = checkinAppointment,
        _rescheduleAppointment = rescheduleAppointment,
        _listSlots = listSlots,
        _listPractitioners = listPractitioners,
        super(const AgendaInitial()) {
    on<AgendaLoadRequested>(_onLoad);
    on<AgendaAppointmentCreateRequested>(_onCreate);
    on<AgendaAppointmentConfirmRequested>(_onConfirm);
    on<AgendaAppointmentCheckinRequested>(_onCheckin);
    on<AgendaAppointmentRescheduleRequested>(_onReschedule);
  }

  Future<void> _onLoad(
    AgendaLoadRequested event,
    Emitter<AgendaState> emit,
  ) async {
    _currentWeekStart = event.weekStart;
    emit(const AgendaLoading());
    try {
      final entriesResult = await _getAgenda(event.weekStart);
      if (entriesResult.isLeft()) {
        final failure = entriesResult.fold((f) => f, (_) => null)!;
        safeEmit(AgendaError(failure.message));
        return;
      }
      final slotsResult = await _listSlots(
        from: event.weekStart,
        to: event.weekStart.add(const Duration(days: 7)),
      );
      final entries = entriesResult.getOrElse(() => []);
      final slots = slotsResult.getOrElse(() => []);
      // #4666 : la map practitionerId -> nom ne doit pas être construite à
      // partir des seules `entries` de la semaine affichée (vide ou
      // incomplète si un praticien n'a aucun créneau/RDV cette semaine-là).
      // On réutilise le roster du cabinet (même source que le picker
      // « Nouveau RDV », #4608) — résolution qui reste correcte même sur une
      // semaine vide.
      final practitionersResult = await _listPractitioners();
      final practitionerNames = <String, String>{
        for (final p in practitionersResult.getOrElse(() => []))
          p.id: p.displayName,
      };
      safeEmit(AgendaLoaded(
        entries: entries,
        availableSlots: slots,
        practitionerNames: practitionerNames,
        weekStart: event.weekStart,
      ));
    } catch (_) {
      safeEmit(const AgendaError('Erreur de chargement de l\'agenda.'));
    }
  }

  Future<void> _onCreate(
    AgendaAppointmentCreateRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _createAppointment(event.appointment);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) {
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
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
      result.fold(
        (failure) {
          safeEmit(current.copyWith(
            actionInProgress: false,
            actionError: failure.message,
          ));
          // #4535 : recharge même sur échec — un 409 peut signifier que le
          // RDV a changé de statut entre-temps (déjà confirmé, annulé…),
          // l'agenda affichée doit refléter l'état réel, pas rester figée
          // sur "À confirmer" pendant que le snackbar d'erreur s'affiche.
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
        (_) {
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onCheckin(
    AgendaAppointmentCheckinRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result = await _checkinAppointment(event.appointmentId);
      result.fold(
        (failure) {
          safeEmit(current.copyWith(
            actionInProgress: false,
            actionError: failure.message,
          ));
          // Même logique que _onConfirm (#4535) : un 409 peut signifier que
          // le RDV a changé de statut entre-temps — l'agenda doit refléter
          // l'état réel, pas rester figée sur "Confirmé".
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
        (_) {
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }

  Future<void> _onReschedule(
    AgendaAppointmentRescheduleRequested event,
    Emitter<AgendaState> emit,
  ) async {
    final current = state;
    if (current is! AgendaLoaded) return;
    emit(current.copyWith(actionInProgress: true, clearActionError: true));
    try {
      final result =
          await _rescheduleAppointment(event.appointmentId, event.newStartsAt);
      result.fold(
        (failure) => safeEmit(current.copyWith(
          actionInProgress: false,
          actionError: failure.message,
        )),
        (_) {
          if (_currentWeekStart != null) {
            add(AgendaLoadRequested(weekStart: _currentWeekStart!));
          }
        },
      );
    } catch (_) {
      safeEmit(current.copyWith(
          actionInProgress: false, actionError: 'Erreur inattendue.'));
    }
  }
}
