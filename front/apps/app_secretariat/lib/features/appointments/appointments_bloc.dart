import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'appointments_event.dart';
import 'appointments_state.dart';

class AppointmentsBloc extends Bloc<AppointmentsEvent, AppointmentsState> {
  final CreateCabinetAppointmentUseCase _create;
  final ConfirmAppointmentUseCase _confirm;
  final RescheduleAppointmentUseCase _reschedule;

  AppointmentsBloc({
    required CreateCabinetAppointmentUseCase create,
    required ConfirmAppointmentUseCase confirm,
    required RescheduleAppointmentUseCase reschedule,
  })  : _create = create,
        _confirm = confirm,
        _reschedule = reschedule,
        super(const AppointmentsInitial()) {
    on<AppointmentCreateRequested>(_onCreate);
    on<AppointmentConfirmRequested>(_onConfirm);
    on<AppointmentRescheduleRequested>(_onReschedule);
  }

  Future<void> _onCreate(
    AppointmentCreateRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    final result = await _create(event.appointment);
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (appointment) => emit(AppointmentSuccess(appointment)),
    );
  }

  Future<void> _onConfirm(
    AppointmentConfirmRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    final result = await _confirm(event.appointmentId);
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (appointment) => emit(AppointmentSuccess(appointment)),
    );
  }

  Future<void> _onReschedule(
    AppointmentRescheduleRequested event,
    Emitter<AppointmentsState> emit,
  ) async {
    emit(const AppointmentsLoading());
    final result = await _reschedule(event.appointmentId, event.newStartsAt);
    result.fold(
      (failure) => emit(AppointmentsError(failure.message)),
      (appointment) => emit(AppointmentSuccess(appointment)),
    );
  }
}
