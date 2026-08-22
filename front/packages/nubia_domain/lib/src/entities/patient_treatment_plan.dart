import 'package:equatable/equatable.dart';

/// Un acte rattaché à une phase d'un plan de traitement patient (#4261).
class PatientTreatmentPlanItem extends Equatable {
  final String label;
  final String? ccamCode;
  final int unitAmountCents;
  final int amoPartCents;
  final int amcPartCents;

  const PatientTreatmentPlanItem({
    required this.label,
    this.ccamCode,
    required this.unitAmountCents,
    required this.amoPartCents,
    required this.amcPartCents,
  });

  @override
  List<Object?> get props => [label, ccamCode, unitAmountCents];
}

/// État de couverture financière d'une phase — dit honnêtement si le
/// montant affiché est déjà réglé, couvert par un devis signé (phase
/// confirmée ou en cours), ou une simple estimation (#5298).
enum PatientTreatmentPlanPhaseCoverage { paid, covered, estimated }

/// Une phase d'un plan de traitement patient, avec ses actes (#4261).
class PatientTreatmentPlanPhase extends Equatable {
  final String id;
  final int position;
  final String title;
  final String status;
  final List<PatientTreatmentPlanItem> items;

  /// Devis envoyé et en attente de signature du patient pour cette phase,
  /// s'il y en a un — bandeau « devis en attente » (#5300). `null` si la
  /// phase n'est bloquée par aucun devis en attente d'accord.
  final String? pendingQuoteId;
  final DateTime? pendingQuoteSentAt;

  /// Rendez-vous programmé pour cette phase, s'il y en a un — CTA « Voir
  /// mon rendez-vous » sur la phase en cours (#5299). `null` si aucune
  /// séance n'est programmée pour cette phase.
  final String? appointmentId;
  final DateTime? appointmentAt;

  const PatientTreatmentPlanPhase({
    required this.id,
    required this.position,
    required this.title,
    required this.status,
    this.items = const [],
    this.pendingQuoteId,
    this.pendingQuoteSentAt,
    this.appointmentId,
    this.appointmentAt,
  });

  /// Montant agrégé de la phase — somme des actes (#5298). Affiché avec le
  /// libellé [coverage] plutôt que la liste brute des actes.
  int get amountCents =>
      items.fold(0, (total, item) => total + item.unitAmountCents);

  /// Statut de paiement de la phase, dérivé de [status] (#5298) : réglée
  /// (`done`), couverte par un devis déjà signé (`confirmed`/`in_progress`),
  /// ou simple estimation (`requested`/autre).
  PatientTreatmentPlanPhaseCoverage get coverage {
    switch (status) {
      case 'done':
        return PatientTreatmentPlanPhaseCoverage.paid;
      case 'confirmed':
      case 'in_progress':
        return PatientTreatmentPlanPhaseCoverage.covered;
      default:
        return PatientTreatmentPlanPhaseCoverage.estimated;
    }
  }

  @override
  List<Object?> get props => [id];
}

/// Plan de traitement patient (#4261). Source :
/// `GET /v1/treatment-plans` (liste, id/title/status/createdAt seulement) et
/// `GET /v1/treatment-plans/:id` (détail, coûts + phases — pas de createdAt).
/// Les champs absents de la variante chargée restent `null`/vides plutôt que
/// fabriqués — reflète fidèlement l'asymétrie liste/détail de l'API.
class PatientTreatmentPlan extends Equatable {
  final String id;
  final String title;
  final String status;
  final DateTime? createdAt;
  final int? totalCostCents;
  final int? remainingCents;
  final int? amoPartCents;
  final int? amcPartCents;
  final List<PatientTreatmentPlanPhase> phases;

  const PatientTreatmentPlan({
    required this.id,
    required this.title,
    required this.status,
    this.createdAt,
    this.totalCostCents,
    this.remainingCents,
    this.amoPartCents,
    this.amcPartCents,
    this.phases = const [],
  });

  /// Somme des actes des phases déjà réalisées (`done`) — considérés réglés.
  /// Bloc « Coût de votre plan » (#5301).
  int get paidCents => _sumItemsWhereStatusIn(const {'done'});

  /// Somme des actes des phases confirmées ou en cours (`confirmed`,
  /// `in_progress`) — couvertes par un devis déjà signé mais pas encore
  /// soldées. Bloc « Coût de votre plan » (#5301).
  int get committedCents =>
      _sumItemsWhereStatusIn(const {'confirmed', 'in_progress'});

  /// Somme des actes des phases simplement demandées (`requested`) — devis
  /// pas encore signé par le patient. Bloc « Coût de votre plan » (#5301).
  int get pendingApprovalCents => _sumItemsWhereStatusIn(const {'requested'});

  int _sumItemsWhereStatusIn(Set<String> statuses) {
    var total = 0;
    for (final phase in phases) {
      if (!statuses.contains(phase.status)) continue;
      for (final item in phase.items) {
        total += item.unitAmountCents;
      }
    }
    return total;
  }

  @override
  List<Object?> get props => [id];
}
