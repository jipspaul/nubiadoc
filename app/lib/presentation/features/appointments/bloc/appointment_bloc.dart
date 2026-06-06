import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_history_use_case.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_upcoming_appointments_use_case.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class AppointmentEvent extends Equatable {
  const AppointmentEvent();

  @override
  List<Object?> get props => [];
}

class AppointmentLoadRequested extends AppointmentEvent {
  const AppointmentLoadRequested();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class AppointmentState extends Equatable {
  const AppointmentState();

  @override
  List<Object?> get props => [];
}

class AppointmentInitial extends AppointmentState {
  const AppointmentInitial();
}

class AppointmentLoading extends AppointmentState {
  const AppointmentLoading();
}

class AppointmentLoaded extends AppointmentState {
  final List<Appointment> upcoming;
  final List<Appointment> history;

  const AppointmentLoaded({
    required this.upcoming,
    required this.history,
  });

  @override
  List<Object?> get props => [upcoming, history];
}

class AppointmentError extends AppointmentState {
  final String message;

  const AppointmentError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class AppointmentBloc extends Bloc<AppointmentEvent, AppointmentState> {
  final GetUpcomingAppointmentsUseCase _getUpcoming;
  final GetAppointmentHistoryUseCase _getHistory;

  AppointmentBloc(this._getUpcoming, this._getHistory)
      : super(const AppointmentInitial()) {
    on<AppointmentLoadRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    AppointmentLoadRequested event,
    Emitter<AppointmentState> emit,
  ) async {
    emit(const AppointmentLoading());

    final upcomingResult = await _getUpcoming();
    final upcomingFailed = upcomingResult.isLeft();
    if (upcomingFailed) {
      final failure = upcomingResult.fold((f) => f, (_) => null)!;
      emit(AppointmentError(failure.message));
      return;
    }

    final historyResult = await _getHistory();
    historyResult.fold(
      (failure) => emit(AppointmentError(failure.message)),
      (history) => emit(
        AppointmentLoaded(
          upcoming: upcomingResult.getOrElse(() => []),
          history: history,
        ),
      ),
    );
  }
}
