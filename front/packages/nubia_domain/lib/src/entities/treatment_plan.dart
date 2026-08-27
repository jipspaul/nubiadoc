import 'package:equatable/equatable.dart';

/// Référence du devis (`devis`, feature séparée) auquel une [TreatmentPhase]
/// est rattachée — lien entre `treatment_plans` et `devis` à l'écran.
class TreatmentPhaseQuoteRef extends Equatable {
  final String quoteNumber;
  final DateTime? signedAt;
  final bool depositPaid;

  const TreatmentPhaseQuoteRef({
    required this.quoteNumber,
    this.signedAt,
    this.depositPaid = false,
  });

  @override
  List<Object?> get props => [quoteNumber, signedAt, depositPaid];
}

/// Acte rattaché à une phase (#5012, maquette design-v2 point 2, `.act`) :
/// libellé, code CCAM, dent et montant, source de [TreatmentPhase.totalCents]
/// (#5013). `label`/`ccamCode`/`subtitle` par défaut vides et `tooth` nul
/// pour rester compatible avec les actes déjà construits côté #5013 (montant
/// seul) tant que le back n'expose pas encore le détail complet.
class TreatmentPhaseAct extends Equatable {
  final String id;
  final String label;
  final String? ccamCode;

  /// Numéro de dent (ex. « 26 »). `null` si l'acte n'est pas rattaché à une
  /// dent précise.
  final String? tooth;
  final int amountCents;

  /// Sous-titre libre (ex. « Réalisé le 22/07 », « À programmer »). `null`
  /// si absent.
  final String? subtitle;

  const TreatmentPhaseAct({
    required this.id,
    this.label = '',
    this.ccamCode,
    this.tooth,
    required this.amountCents,
    this.subtitle,
  });

  @override
  List<Object?> get props =>
      [id, label, ccamCode, tooth, amountCents, subtitle];
}

class TreatmentPhase extends Equatable {
  final String id;
  final int position;
  final String title;
  final String status;

  /// Null = aucun devis rattaché à cette phase (le patient n'a pas encore
  /// accepté cette phase).
  final TreatmentPhaseQuoteRef? quoteRef;

  /// Actes rattachés à la phase (#5013), source de [totalCents]. Vide tant
  /// que le back n'expose pas encore ces actes pour une phase praticien.
  final List<TreatmentPhaseAct> acts;

  const TreatmentPhase({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.quoteRef,
    this.acts = const [],
  });

  bool get isCovered => quoteRef != null;

  /// Montant total de la phase — somme des [acts] (#5013).
  int get totalCents =>
      acts.fold(0, (total, act) => total + act.amountCents);

  @override
  List<Object?> get props => [id, position, title, status, quoteRef, acts];
}

class TreatmentPlan extends Equatable {
  final String id;
  final String title;
  final String status;
  final DateTime createdAt;
  final List<TreatmentPhase> phases;

  const TreatmentPlan({
    required this.id,
    required this.title,
    required this.status,
    required this.createdAt,
    required this.phases,
  });

  /// Total du plan — somme du [TreatmentPhase.totalCents] de chaque phase
  /// (#5013).
  int get totalCents =>
      phases.fold(0, (total, phase) => total + phase.totalCents);

  /// Engagé — somme des [TreatmentPhase.totalCents] des phases couvertes par
  /// un devis déjà signé (#5013). Une phase `done` a nécessairement été
  /// signée au préalable, donc [realizedCents] est toujours inclus ici.
  int get engagedCents => phases
      .where((phase) => phase.quoteRef?.signedAt != null)
      .fold(0, (total, phase) => total + phase.totalCents);

  /// Réalisé — somme des [TreatmentPhase.totalCents] des phases terminées
  /// (#5013).
  int get realizedCents => phases
      .where((phase) => phase.status == 'done')
      .fold(0, (total, phase) => total + phase.totalCents);

  /// Reste à deviser — part du total du plan non couverte par un devis signé
  /// (#5013), affichée au footer (« X non couverts par aucun devis »).
  int get remainingToQuoteCents => totalCents - engagedCents;

  @override
  List<Object?> get props => [id, title, status, createdAt, phases];
}
