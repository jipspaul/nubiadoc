import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState>
    with SafeEmitMixin<AppointmentsState> {
  final ListCabinetAppointmentsUseCase _list;
  final CreateCabinetAppointmentUseCase _create;
  final ConfirmAppointmentUseCase _confirm;
  final RescheduleAppointmentUseCase _reschedule;

  AppointmentsBloc({
    required ListCabinetAppointmentsUseCase listAppointments,
    required CreateCabinetAppointmentUseCase create,
    required ConfirmAppointmentUseCase confirm,
    required RescheduleAppointmentUseCase reschedule,
  })  : _list = listAppointments,
        _create = create,
        _confirm = confirm,
        _reschedule = reschedule,
        super(const AppointmentsInitial()) {
    on<AppointmentsLoadRequested>(_onLoad);
    on<AppointmentCreateRequested>(_onCreate);
    on<AppointmentConfirmRequested>(_onConfirm);
    on<AppointmentRescheduleRequested>(_onReschedule);
  }

  Future<void> _onLoad(
    AppointmentsLoadRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    try {
      // `fromDate` (#8180) : ancre la page sur aujourd'hui — sans ce filtre,
      // la liste par défaut (`ORDER BY starts_at ASC`) ne remonte que les
      // RDV les plus anciens du cabinet sur une base volumineuse, si bien
      // que le tri "actionnable maintenant" de `_LoadedView._filtered`
      // (#6833) n'avait en pratique jamais aucun RDV récent/futur à trier.
      final result = await _list(fromDate: DateTime.now());
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointments) => safeEmit(AppointmentsLoaded(appointments)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de chargement.'));
    }
  }

  Future<void> _onCreate(
    AppointmentCreateRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    try {
      final result = await _create(event.appointment);
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointment) => safeEmit(AppointmentSuccess(appointment)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de chargement.'));
    }
  }

  Future<void> _onConfirm(
    AppointmentConfirmRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    try {
      final result = await _confirm(event.appointmentId);
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointment) => safeEmit(AppointmentSuccess(appointment)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de chargement.'));
    }
  }

  Future<void> _onReschedule(
    AppointmentRescheduleRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    try {
      final result = await _reschedule(event.appointmentId, event.newStartsAt);
      result.fold(
        (failure) => safeEmit(AppointmentsError(failure.message)),
        (appointment) => safeEmit(AppointmentSuccess(appointment)),
      );
    } catch (_) {
      safeEmit(const AppointmentsError('Erreur de chargement.'));
    }
  }
}
