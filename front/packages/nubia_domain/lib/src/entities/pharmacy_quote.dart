import 'package:equatable/equatable.dart';

/// Statuts d'un devis d'officine.
enum PharmacyQuoteStatus { draft, sent, accepted, refused, expired }

/// Une ligne d'un devis d'officine (produit, prix TTC en centimes).
///
/// `amoPartCents`/`amcPartCents` (#6897) : part du **total de la ligne**
/// (pas du prix unitaire) prise en charge par l'AMO/l'AMC, saisie
/// déclarativement à la création du devis. `0`/`0` (défaut historique) =
/// ligne non ventilée, part patient = prix de la ligne.
class PharmacyQuoteItem extends Equatable {
  final String label;
  final int quantity;
  final int unitPriceCents;
  final int amoPartCents;
  final int amcPartCents;

  const PharmacyQuoteItem({
    required this.label,
    required this.quantity,
    required this.unitPriceCents,
    this.amoPartCents = 0,
    this.amcPartCents = 0,
  });

  int get totalCents => quantity * unitPriceCents;

  @override
  List<Object?> get props =>
      [label, quantity, unitPriceCents, amoPartCents, amcPartCents];
}

/// Devis d'officine (pharmacie → patient), distinct du devis dentaire.
class PharmacyQuote extends Equatable {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;
  final String? orderId;

  /// Référence courte affichable (`DEV-P-0042`), dérivée de `quote_seq`
  /// (#7141) — même pattern que `PharmacyOrder.orderRef` (#6253).
  final String? quoteRef;
  final List<PharmacyQuoteItem> items;
  final int totalCents;
  final PharmacyQuoteStatus status;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? decidedAt;

  /// Dernière relance manuelle (#6900) — `null` tant que « Relancer » n'a
  /// jamais été appelé avec succès sur ce devis.
  final DateTime? remindedAt;
  final int reminderCount;

  const PharmacyQuote({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.patientDisplayName,
    this.orderId,
    this.quoteRef,
    required this.items,
    required this.totalCents,
    required this.status,
    required this.createdAt,
    this.sentAt,
    this.decidedAt,
    this.remindedAt,
    this.reminderCount = 0,
  });

  /// Le patient ne peut décider que d'un devis envoyé.
  bool get isDecidable => status == PharmacyQuoteStatus.sent;

  @override
  List<Object?> get props => [id, status, remindedAt, reminderCount];
}
