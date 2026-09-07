import 'package:equatable/equatable.dart';

/// Évènements du parcours devis / plan de traitement (vue praticien).
abstract class DevisEvent extends Equatable {
  const DevisEvent();

  @override
  List<Object?> get props => [];
}

/// Charge (ou recharge) la liste des devis du cabinet.
///
/// [patientId] non nul ⇒ filtre côté serveur (`patient_id`, #4419/#5572) sur
/// ce seul patient, au lieu du cabinet entier (#6672 : le CTA « Générer le
/// devis de la phase N » du plan de traitement doit rester scopé au patient
/// dont le plan est ouvert).
class DevisListRequested extends DevisEvent {
  final String? patientId;

  const DevisListRequested({this.patientId});

  @override
  List<Object?> get props => [patientId];
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
