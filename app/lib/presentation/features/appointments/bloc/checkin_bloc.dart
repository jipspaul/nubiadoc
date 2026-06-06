import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/checkin_appointment_use_case.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class CheckinEvent extends Equatable {
  const CheckinEvent();

  @override
  List<Object?> get props => [];
}

class CheckinRequested extends CheckinEvent {
  final String appointmentId;

  const CheckinRequested(this.appointmentId);

  @override
  List<Object?> get props => [appointmentId];
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class CheckinState extends Equatable {
  const CheckinState();

  @override
  List<Object?> get props => [];
}

class CheckinInitial extends CheckinState {
  const CheckinInitial();
}

class CheckinInProgress extends CheckinState {
  const CheckinInProgress();
}

class CheckinSuccess extends CheckinState {
  final Appointment appointment;

  const CheckinSuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class CheckinFailure extends CheckinState {
  final String message;

  const CheckinFailure(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class CheckinBloc extends Bloc<CheckinEvent, CheckinState> {
  final CheckinAppointmentUseCase _checkin;

  CheckinBloc(this._checkin) : super(const CheckinInitial()) {
    on<CheckinRequested>(_onCheckinRequested);
  }

  Future<void> _onCheckinRequested(
    CheckinRequested event,
    Emitter<CheckinState> emit,
  ) async {
    emit(const CheckinInProgress());
    final result = await _checkin(event.appointmentId);
    result.fold(
      (failure) => emit(CheckinFailure(failure.message)),
      (appointment) => emit(CheckinSuccess(appointment)),
    );
  }
}
