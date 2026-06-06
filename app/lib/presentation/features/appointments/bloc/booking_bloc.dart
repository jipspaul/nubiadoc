import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/book_appointment_use_case.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_upcoming_appointments_use_case.dart';

// ---------------------------------------------------------------------------
// Slot value object
// ---------------------------------------------------------------------------

class AppointmentSlot extends Equatable {
  final String id;
  final DateTime startsAt;
  final Duration duration;
  final bool available;

  const AppointmentSlot({
    required this.id,
    required this.startsAt,
    required this.duration,
    required this.available,
  });

  @override
  List<Object?> get props => [id, available];
}

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

abstract class BookingEvent extends Equatable {
  const BookingEvent();

  @override
  List<Object?> get props => [];
}

class BookingLoadRequested extends BookingEvent {
  const BookingLoadRequested();
}

class BookingSlotSelected extends BookingEvent {
  final AppointmentSlot slot;

  const BookingSlotSelected(this.slot);

  @override
  List<Object?> get props => [slot];
}

class BookingMotifChanged extends BookingEvent {
  final String motif;

  const BookingMotifChanged(this.motif);

  @override
  List<Object?> get props => [motif];
}

class BookingSubmitted extends BookingEvent {
  const BookingSubmitted();
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

abstract class BookingState extends Equatable {
  const BookingState();

  @override
  List<Object?> get props => [];
}

class BookingInitial extends BookingState {
  const BookingInitial();
}

class BookingLoading extends BookingState {
  const BookingLoading();
}

class BookingLoaded extends BookingState {
  final List<AppointmentSlot> slots;
  final AppointmentSlot? selectedSlot;
  final String motif;
  final bool submitting;

  const BookingLoaded({
    required this.slots,
    this.selectedSlot,
    this.motif = '',
    this.submitting = false,
  });

  BookingLoaded copyWith({
    List<AppointmentSlot>? slots,
    AppointmentSlot? selectedSlot,
    bool clearSelectedSlot = false,
    String? motif,
    bool? submitting,
  }) {
    return BookingLoaded(
      slots: slots ?? this.slots,
      selectedSlot:
          clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      motif: motif ?? this.motif,
      submitting: submitting ?? this.submitting,
    );
  }

  @override
  List<Object?> get props => [slots, selectedSlot, motif, submitting];
}

class BookingSuccess extends BookingState {
  final Appointment appointment;

  const BookingSuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class BookingError extends BookingState {
  final String message;

  const BookingError(this.message);

  @override
  List<Object?> get props => [message];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

@injectable
class BookingBloc extends Bloc<BookingEvent, BookingState> {
  final GetUpcomingAppointmentsUseCase _getUpcoming;
  final BookAppointmentUseCase _book;

  BookingBloc(this._getUpcoming, this._book) : super(const BookingInitial()) {
    on<BookingLoadRequested>(_onLoadRequested);
    on<BookingSlotSelected>(_onSlotSelected);
    on<BookingMotifChanged>(_onMotifChanged);
    on<BookingSubmitted>(_onSubmitted);
  }

  Future<void> _onLoadRequested(
    BookingLoadRequested event,
    Emitter<BookingState> emit,
  ) async {
    emit(const BookingLoading());
    final result = await _getUpcoming();
    result.fold(
      (failure) => emit(BookingError(failure.message)),
      (upcoming) {
        // Build synthetic slots from existing appointments for anti-double-booking UI.
        // In a real implementation the API would return available slots directly.
        final takenSlotIds = upcoming
            .where((a) =>
                a.status == AppointmentStatus.confirmed ||
                a.status == AppointmentStatus.requested)
            .map((a) => a.id)
            .toSet();

        // Produce next 5 business-day slots (placeholder until API slot endpoint exists).
        final now = DateTime.now();
        final slots = List.generate(10, (i) {
          final base = now.add(Duration(days: i + 1));
          final morning = DateTime(base.year, base.month, base.day, 9, 0);
          return AppointmentSlot(
            id: 'slot-${base.toIso8601String()}',
            startsAt: morning,
            duration: const Duration(minutes: 30),
            available: !takenSlotIds.contains('slot-${base.toIso8601String()}'),
          );
        });

        emit(BookingLoaded(slots: slots));
      },
    );
  }

  void _onSlotSelected(
    BookingSlotSelected event,
    Emitter<BookingState> emit,
  ) {
    final current = state;
    if (current is! BookingLoaded || !event.slot.available) return;
    emit(current.copyWith(selectedSlot: event.slot));
  }

  void _onMotifChanged(
    BookingMotifChanged event,
    Emitter<BookingState> emit,
  ) {
    final current = state;
    if (current is! BookingLoaded) return;
    emit(current.copyWith(motif: event.motif));
  }

  Future<void> _onSubmitted(
    BookingSubmitted event,
    Emitter<BookingState> emit,
  ) async {
    final current = state;
    if (current is! BookingLoaded) return;
    final slot = current.selectedSlot;
    if (slot == null || current.motif.trim().isEmpty) return;

    emit(current.copyWith(submitting: true));
    final result = await _book(slotId: slot.id, motif: current.motif.trim());
    result.fold(
      (failure) => emit(BookingError(failure.message)),
      (appointment) => emit(BookingSuccess(appointment)),
    );
  }
}
