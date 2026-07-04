import 'package:equatable/equatable.dart';

/// Statuts d'un devis d'officine.
enum PharmacyQuoteStatus { draft, sent, accepted, refused, expired }

/// Une ligne d'un devis d'officine (produit, prix TTC en centimes).
class PharmacyQuoteItem extends Equatable {
  final String label;
  final int quantity;
  final int unitPriceCents;

  const PharmacyQuoteItem({
    required this.label,
    required this.quantity,
    required this.unitPriceCents,
  });

  int get totalCents => quantity * unitPriceCents;

  @override
  List<Object?> get props => [label, quantity, unitPriceCents];
}

/// Devis d'officine (pharmacie → patient), distinct du devis dentaire.
class PharmacyQuote extends Equatable {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;
  final String? orderId;
  final List<PharmacyQuoteItem> items;
  final int totalCents;
  final PharmacyQuoteStatus status;
  final DateTime createdAt;
  final DateTime? sentAt;
  final DateTime? decidedAt;

  const PharmacyQuote({
    required this.id,
    required this.pharmacyId,
    this.pharmacyName,
    this.patientDisplayName,
    this.orderId,
    required this.items,
    required this.totalCents,
    required this.status,
    required this.createdAt,
    this.sentAt,
    this.decidedAt,
  });

  /// Le patient ne peut décider que d'un devis envoyé.
  bool get isDecidable => status == PharmacyQuoteStatus.sent;

  @override
  List<Object?> get props => [id, status];
}
