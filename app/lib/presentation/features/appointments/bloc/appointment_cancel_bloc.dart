import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/cancel_appointment_use_case.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class AppointmentCancelEvent extends Equatable {
  const AppointmentCancelEvent();

  @override
  List<Object?> get props => [];
}

class AppointmentCancelRequested extends AppointmentCancelEvent {
  final Appointment appointment;
  final String reason;

  const AppointmentCancelRequested({
    required this.appointment,
    required this.reason,
  });

  @override
  List<Object?> get props => [appointment, reason];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class AppointmentCancelState extends Equatable {
  const AppointmentCancelState();

  @override
  List<Object?> get props => [];
}

class AppointmentCancelInitial extends AppointmentCancelState {
  const AppointmentCancelInitial();
}

class AppointmentCancelInProgress extends AppointmentCancelState {
  const AppointmentCancelInProgress();
}

class AppointmentCancelSuccess extends AppointmentCancelState {
  final Appointment appointment;

  const AppointmentCancelSuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class AppointmentCancelFailure extends AppointmentCancelState {
  final String message;

  const AppointmentCancelFailure(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class AppointmentCancelBloc
    extends Bloc<AppointmentCancelEvent, AppointmentCancelState> {
  final CancelAppointmentUseCase _cancel;

  AppointmentCancelBloc(this._cancel)
      : super(const AppointmentCancelInitial()) {
    on<AppointmentCancelRequested>(_onCancelRequested);
  }

  Future<void> _onCancelRequested(
    AppointmentCancelRequested event,
    Emitter<AppointmentCancelState> emit,
  ) async {
    emit(const AppointmentCancelInProgress());
    final result = await _cancel(event.appointment);
    result.fold(
      (failure) => emit(AppointmentCancelFailure(failure.message)),
      (appointment) => emit(AppointmentCancelSuccess(appointment)),
    );
  }
}
