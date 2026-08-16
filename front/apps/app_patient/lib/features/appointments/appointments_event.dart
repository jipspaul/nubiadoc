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
  // #5357 : posé quand la sélection vient d'un clic sur une puce créneau de
  // la carte résultat (bloc `.slots`) — une fois l'agenda complet chargé, ce
  // créneau est automatiquement sélectionné (et son hold posé si
  // authentifié) pour enchaîner directement sur la réservation.
  final String? preselectSlotId;
  const AppointmentsProviderSelected(this.provider, {this.preselectSlotId});

  @override
  List<Object?> get props => [provider, preselectSlotId];
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

/// #5362 : un visiteur anonyme confirme son RDV et crée son compte dans le
/// même formulaire — les champs "Vos informations" ne sont renseignés (et
/// pris en compte) que lorsque [createAccount] vaut `true` (l'utilisateur
/// n'a pas encore de session).
class AppointmentsBookingConfirmed extends AppointmentsEvent {
  const AppointmentsBookingConfirmed({
    this.firstName = '',
    this.lastName = '',
    this.dateOfBirth,
    this.phone = '',
    this.email = '',
    this.precisions = '',
    this.createAccount = false,
    this.remindersEnabled = true,
    this.cguAccepted = false,
  });

  final String firstName;
  final String lastName;
  final DateTime? dateOfBirth;
  final String phone;
  final String email;
  final String precisions;
  final bool createAccount;
  final bool remindersEnabled;
  final bool cguAccepted;

  @override
  List<Object?> get props => [
        firstName,
        lastName,
        dateOfBirth,
        phone,
        email,
        precisions,
        createAccount,
        remindersEnabled,
        cguAccepted,
      ];
}

/// Le verrou de 10 min (#5363) est arrivé à expiration côté client (décompte
/// du récapitulatif à zéro) : le créneau redevient sélectionnable, l'ancien
/// hold_token n'est plus valide côté API.
class AppointmentsHoldExpired extends AppointmentsEvent {
  const AppointmentsHoldExpired();
}

/// Retour à la liste des praticiens depuis les créneaux (bouton retour
/// système/AppBar, geste swipe-back).
class AppointmentsBackToSearch extends AppointmentsEvent {
  const AppointmentsBackToSearch();
}
