import 'package:equatable/equatable.dart';
import 'package:nubia_domain/nubia_domain.dart';

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

/// Génère un devis brouillon pré-rempli depuis les actes d'une phase de plan
/// de traitement (#6914) — le CTA contextuel « Générer le devis de la phase
/// N » (`CoverageColumn`/`PhaseQuoteBanner`) ne faisait jusqu'ici que
/// naviguer vers la liste générique des devis du patient, sans rien produire.
/// Transmis en `extra` de la route `/devis` (les lignes d'actes ne se
/// prêtent pas à une query string).
class DevisGenerateFromPhaseRequested extends DevisEvent {
  final String patientId;
  final List<QuoteLineItem> items;
  final String phaseLabel;

  const DevisGenerateFromPhaseRequested({
    required this.patientId,
    required this.items,
    required this.phaseLabel,
  });

  @override
  List<Object?> get props => [patientId, items, phaseLabel];
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
