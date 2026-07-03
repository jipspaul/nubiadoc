import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

abstract class AppointmentsEvent extends Equatable {
  const AppointmentsEvent();

  @override
  List<Object?> get props => [];
}

class AppointmentsSearchChanged extends AppointmentsEvent {
  final String query;
  const AppointmentsSearchChanged(this.query);

  @override
  List<Object?> get props => [query];
}

class AppointmentsProviderSelected extends AppointmentsEvent {
  final ProviderResult provider;
  const AppointmentsProviderSelected(this.provider);

  @override
  List<Object?> get props => [provider];
}

class AppointmentsSlotSelected extends AppointmentsEvent {
  final Slot slot;
  const AppointmentsSlotSelected(this.slot);

  @override
  List<Object?> get props => [slot];
}

class AppointmentsMotifChanged extends AppointmentsEvent {
  final String motif;
  const AppointmentsMotifChanged(this.motif);

  @override
  List<Object?> get props => [motif];
}

class AppointmentsBookingConfirmed extends AppointmentsEvent {
  const AppointmentsBookingConfirmed();
}

/// Retour à la liste des praticiens depuis les créneaux (bouton retour
/// système/AppBar, geste swipe-back).
class AppointmentsBackToSearch extends AppointmentsEvent {
  const AppointmentsBackToSearch();
}
