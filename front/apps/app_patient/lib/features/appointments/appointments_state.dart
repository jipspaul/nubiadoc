import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class AppointmentsState extends Equatable {
  const AppointmentsState();

  @override
  List<Object?> get props => [];
}

class AppointmentsInitial extends AppointmentsState {
  const AppointmentsInitial();
}

class AppointmentsSearchLoading extends AppointmentsState {
  const AppointmentsSearchLoading();
}

class AppointmentsProvidersLoaded extends AppointmentsState {
  final List<ProviderResult> providers;
  final String query;

  const AppointmentsProvidersLoaded({
    required this.providers,
    required this.query,
  });

  @override
  List<Object?> get props => [providers, query];
}

class AppointmentsSlotsLoading extends AppointmentsState {
  final ProviderResult provider;
  const AppointmentsSlotsLoading(this.provider);

  @override
  List<Object?> get props => [provider];
}

class AppointmentsSlotsLoaded extends AppointmentsState {
  final ProviderResult provider;
  final List<Slot> slots;
  final Slot? selectedSlot;
  final String motif;

  const AppointmentsSlotsLoaded({
    required this.provider,
    required this.slots,
    this.selectedSlot,
    this.motif = '',
  });

  AppointmentsSlotsLoaded copyWith({
    Slot? selectedSlot,
    bool clearSelectedSlot = false,
    String? motif,
  }) {
    return AppointmentsSlotsLoaded(
      provider: provider,
      slots: slots,
      selectedSlot:
          clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      motif: motif ?? this.motif,
    );
  }

  @override
  List<Object?> get props => [provider, slots, selectedSlot, motif];
}

class AppointmentsBookingLoading extends AppointmentsState {
  const AppointmentsBookingLoading();
}

class AppointmentsBookingSuccess extends AppointmentsState {
  final Appointment appointment;
  const AppointmentsBookingSuccess(this.appointment);

  @override
  List<Object?> get props => [appointment];
}

class AppointmentsError extends AppointmentsState {
  final String message;
  const AppointmentsError(this.message);

  @override
  List<Object?> get props => [message];
}
