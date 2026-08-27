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

class TreatmentPhase extends Equatable {
  final String id;
  final int position;
  final String title;
  final String status;

  /// Null = aucun devis rattaché à cette phase (le patient n'a pas encore
  /// accepté cette phase).
  final TreatmentPhaseQuoteRef? quoteRef;

  const TreatmentPhase({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.quoteRef,
  });

  bool get isCovered => quoteRef != null;

  @override
  List<Object?> get props => [id, position, title, status, quoteRef];
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

  @override
  List<Object?> get props => [id, title, status, createdAt, phases];
}
