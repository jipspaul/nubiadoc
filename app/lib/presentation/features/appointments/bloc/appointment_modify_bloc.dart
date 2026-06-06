import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/modify_appointment_use_case.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/booking_bloc.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class AppointmentModifyEvent extends Equatable {
  const AppointmentModifyEvent();

  @override
  List<Object?> get props => [];
}

class AppointmentModifyStarted extends AppointmentModifyEvent {
  final Appointment appointment;

  const AppointmentModifyStarted(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class AppointmentModifySlotSelected extends AppointmentModifyEvent {
  final AppointmentSlot slot;

  const AppointmentModifySlotSelected(this.slot);

  @override
  List<Object?> get props => [slot];
}

class AppointmentModifySubmitted extends AppointmentModifyEvent {
  const AppointmentModifySubmitted();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class AppointmentModifyState extends Equatable {
  const AppointmentModifyState();

  @override
  List<Object?> get props => [];
}

class AppointmentModifyInitial extends AppointmentModifyState {
  const AppointmentModifyInitial();
}

class AppointmentModifyReady extends AppointmentModifyState {
  final Appointment original;
  final List<AppointmentSlot> slots;
  final AppointmentSlot? selectedSlot;
  final bool submitting;

  const AppointmentModifyReady({
    required this.original,
    required this.slots,
    this.selectedSlot,
    this.submitting = false,
  });

  AppointmentModifyReady copyWith({
    AppointmentSlot? selectedSlot,
    bool? submitting,
  }) {
    return AppointmentModifyReady(
      original: original,
      slots: slots,
      selectedSlot: selectedSlot ?? this.selectedSlot,
      submitting: submitting ?? this.submitting,
    );
  }

  @override
  List<Object?> get props => [original, slots, selectedSlot, submitting];
}

class AppointmentModifySuccess extends AppointmentModifyState {
  final Appointment appointment;

  const AppointmentModifySuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class AppointmentModifyError extends AppointmentModifyState {
  final String message;

  const AppointmentModifyError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class AppointmentModifyBloc
    extends Bloc<AppointmentModifyEvent, AppointmentModifyState> {
  final ModifyAppointmentUseCase _modify;

  AppointmentModifyBloc(this._modify) : super(const AppointmentModifyInitial()) {
    on<AppointmentModifyStarted>(_onStarted);
    on<AppointmentModifySlotSelected>(_onSlotSelected);
    on<AppointmentModifySubmitted>(_onSubmitted);
  }

  void _onStarted(
    AppointmentModifyStarted event,
    Emitter<AppointmentModifyState> emit,
  ) {
    final now = DateTime.now();
    // Generate the same synthetic slots as BookingBloc.
    final slots = List.generate(10, (i) {
      final base = now.add(Duration(days: i + 1));
      final morning = DateTime(base.year, base.month, base.day, 9, 0);
      return AppointmentSlot(
        id: 'slot-${base.toIso8601String()}',
        startsAt: morning,
        duration: const Duration(minutes: 30),
        available: true,
      );
    });

    emit(AppointmentModifyReady(original: event.appointment, slots: slots));
  }

  void _onSlotSelected(
    AppointmentModifySlotSelected event,
    Emitter<AppointmentModifyState> emit,
  ) {
    final current = state;
    if (current is! AppointmentModifyReady || !event.slot.available) return;
    emit(current.copyWith(selectedSlot: event.slot));
  }

  Future<void> _onSubmitted(
    AppointmentModifySubmitted event,
    Emitter<AppointmentModifyState> emit,
  ) async {
    final current = state;
    if (current is! AppointmentModifyReady) return;
    final slot = current.selectedSlot;
    if (slot == null) return;

    emit(current.copyWith(submitting: true));
    final result =
        await _modify(id: current.original.id, newSlotId: slot.id);
    result.fold(
      (failure) => emit(AppointmentModifyError(failure.message)),
      (appointment) => emit(AppointmentModifySuccess(appointment)),
    );
  }
}
