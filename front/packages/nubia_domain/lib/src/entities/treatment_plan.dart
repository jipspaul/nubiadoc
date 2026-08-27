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

/// Acte minimal nécessaire au calcul des agrégats de montants d'une phase
/// (#5013). Détail complet (libellé, code CCAM, dent, sous-titre...) hors
/// périmètre — voir le ticket domaine « actes rattachés à une phase », pas
/// encore livré (`TreatmentPhase.acts` reste vide en attendant son API).
class TreatmentPhaseAct extends Equatable {
  final String id;
  final int amountCents;

  const TreatmentPhaseAct({required this.id, required this.amountCents});

  @override
  List<Object?> get props => [id, amountCents];
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
