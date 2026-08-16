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
  // hold_token du créneau sélectionné (POST /v1/slots/:id/hold), requis pour
  // confirmer la réservation via POST /v1/bookings.
  final String? holdToken;
  // Expiration du hold (#5363) : pilote le décompte visible du récapitulatif
  // et le déclenchement d'AppointmentsHoldExpired côté UI.
  final DateTime? holdExpiresAt;
  final String motif;

  const AppointmentsSlotsLoaded({
    required this.provider,
    required this.slots,
    this.selectedSlot,
    this.holdToken,
    this.holdExpiresAt,
    this.motif = '',
  });

  AppointmentsSlotsLoaded copyWith({
    Slot? selectedSlot,
    bool clearSelectedSlot = false,
    String? holdToken,
    DateTime? holdExpiresAt,
    String? motif,
  }) {
    return AppointmentsSlotsLoaded(
      provider: provider,
      slots: slots,
      selectedSlot:
          clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      holdToken: clearSelectedSlot ? null : (holdToken ?? this.holdToken),
      holdExpiresAt: clearSelectedSlot
          ? null
          : (holdExpiresAt ?? this.holdExpiresAt),
      motif: motif ?? this.motif,
    );
  }

  @override
  List<Object?> get props =>
      [provider, slots, selectedSlot, holdToken, holdExpiresAt, motif];
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
