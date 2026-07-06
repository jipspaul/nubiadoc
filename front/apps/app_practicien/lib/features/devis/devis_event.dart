import 'package:equatable/equatable.dart';

/// Évènements du parcours devis / plan de traitement (vue praticien).
abstract class DevisEvent extends Equatable {
  const DevisEvent();

  @override
  List<Object?> get props => [];
}

/// Charge (ou recharge) la liste des devis du cabinet.
class DevisListRequested extends DevisEvent {
  const DevisListRequested();
}

/// Ouvre le détail d'un devis (récupère les lignes d'actes complètes).
class DevisQuoteSelected extends DevisEvent {
  final String id;

  const DevisQuoteSelected(this.id);

  @override
  List<Object?> get props => [id];
}

/// Revient à la liste depuis le détail.
class DevisBackToList extends DevisEvent {
  const DevisBackToList();
}

/// Envoie le devis (brouillon) au patient pour signature.
///
/// Déclenche `POST /v1/cabinet/quotes/:id/send` : le devis passe à `sent`
/// côté serveur et devient visible pour le patient (WEDGE, signature eIDAS).
class DevisSendRequested extends DevisEvent {
  final String id;

  const DevisSendRequested(this.id);

  @override
  List<Object?> get props => [id];
}
