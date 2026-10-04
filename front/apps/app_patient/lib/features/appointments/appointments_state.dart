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
  // #5357 : aperçu de 3 jours de créneaux réels par praticien (carte
  // résultat, bloc `.slots`) — indexé par `ProviderResult.id`, rempli une
  // fois les praticiens chargés (repli liste vide tant que non résolu).
  final Map<String, List<Slot>> slotsByProvider;

  const AppointmentsProvidersLoaded({
    required this.providers,
    required this.query,
    this.slotsByProvider = const {},
  });

  @override
  List<Object?> get props => [providers, query, slotsByProvider];
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
  // #7970 : message d'échec de la dernière tentative de confirmation (compte,
  // hold ou réservation) — affiché en SnackBar par la page, sans jamais
  // remplacer cet état déjà chargé (créneau, motif, hold) par un écran
  // d'erreur plein écran (doctrine #7922/#7868). Toujours réinitialisé par
  // `copyWith` à moins d'être explicitement reconduit : un message d'échec ne
  // doit pas survivre à l'interaction suivante.
  final String? bookingError;

  const AppointmentsSlotsLoaded({
    required this.provider,
    required this.slots,
    this.selectedSlot,
    this.holdToken,
    this.holdExpiresAt,
    this.motif = '',
    this.bookingError,
  });

  AppointmentsSlotsLoaded copyWith({
    Slot? selectedSlot,
    bool clearSelectedSlot = false,
    String? holdToken,
    DateTime? holdExpiresAt,
    String? motif,
    String? bookingError,
  }) {
    return AppointmentsSlotsLoaded(
      provider: provider,
      slots: slots,
      selectedSlot:
          clearSelectedSlot ? null : (selectedSlot ?? this.selectedSlot),
      holdToken: clearSelectedSlot ? null : (holdToken ?? this.holdToken),
      holdExpiresAt:
          clearSelectedSlot ? null : (holdExpiresAt ?? this.holdExpiresAt),
      motif: motif ?? this.motif,
      bookingError: bookingError,
    );
  }

  @override
  List<Object?> get props => [
        provider,
        slots,
        selectedSlot,
        holdToken,
        holdExpiresAt,
        motif,
        bookingError,
      ];
}

class AppointmentsBookingLoading extends AppointmentsState {
  // #5343 : repris de l'AppointmentsSlotsLoaded qui précède la confirmation,
  // pour que l'UI garde le récap (créneau + motif) visible sous l'overlay de
  // progression pendant l'appel POST /v1/bookings, plutôt qu'un écran blanc.
  final ProviderResult provider;
  final Slot selectedSlot;
  final String motif;

  const AppointmentsBookingLoading({
    required this.provider,
    required this.selectedSlot,
    required this.motif,
  });

  @override
  List<Object?> get props => [provider, selectedSlot, motif];
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
