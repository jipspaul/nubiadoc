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

/// Création du devis brouillon depuis une phase de plan de traitement en
/// cours (#6914).
class DevisGeneratingFromPhase extends DevisState {
  const DevisGeneratingFromPhase();
}

/// Liste des devis du cabinet.
class DevisListLoaded extends DevisState {
  final List<CabinetQuote> quotes;

  const DevisListLoaded(this.quotes);

  @override
  List<Object?> get props => [quotes];
}

/// Détail d'un devis (lignes d'actes, montants, reste à charge).
///
/// [generatedForPhaseLabel] non nul ⇒ ce devis vient d'être créé depuis le
/// CTA « Générer le devis de la phase N » (#6914) : l'écran affiche un
/// bandeau de provenance (phase/plan) au lieu d'arriver silencieusement sur
/// un détail qui ne dit pas d'où il sort.
class DevisDetailLoaded extends DevisState {
  final CabinetQuote quote;
  final String? generatedForPhaseLabel;

  const DevisDetailLoaded(this.quote, {this.generatedForPhaseLabel});

  @override
  List<Object?> get props => [quote, generatedForPhaseLabel];
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

/// Échec de l'envoi : on reste sur le détail et on signale l'erreur.
class DevisSendFailure extends DevisState {
  final CabinetQuote quote;
  final String message;

  const DevisSendFailure({required this.quote, required this.message});

  @override
  List<Object?> get props => [quote, message];
}

class DevisError extends DevisState {
  final String message;

  const DevisError(this.message);

  @override
  List<Object?> get props => [message];
}
