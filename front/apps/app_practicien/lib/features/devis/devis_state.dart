import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// États du parcours devis / plan de traitement (vue praticien).
abstract class DevisState extends Equatable {
  const DevisState();

  @override
  List<Object?> get props => [];
}

class DevisInitial extends DevisState {
  const DevisInitial();
}

class DevisLoading extends DevisState {
  const DevisLoading();
}

/// Liste des devis du cabinet.
class DevisListLoaded extends DevisState {
  final List<CabinetQuote> quotes;

  const DevisListLoaded(this.quotes);

  @override
  List<Object?> get props => [quotes];
}

/// Détail d'un devis (lignes d'actes, montants, reste à charge).
class DevisDetailLoaded extends DevisState {
  final CabinetQuote quote;

  const DevisDetailLoaded(this.quote);

  @override
  List<Object?> get props => [quote];
}

/// Envoi du devis au patient en cours.
class DevisSendInProgress extends DevisState {
  final CabinetQuote quote;

  const DevisSendInProgress(this.quote);

  @override
  List<Object?> get props => [quote];
}

/// Devis envoyé au patient (confirmation).
class DevisSent extends DevisState {
  final CabinetQuote quote;

  const DevisSent(this.quote);

  @override
  List<Object?> get props => [quote];
}

class DevisError extends DevisState {
  final String message;

  const DevisError(this.message);

  @override
  List<Object?> get props => [message];
}
