import 'package:equatable/equatable.dart';

import 'pharmacy_order.dart';

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

/// Agrégation AMO/AMC d'une liste de lignes de devis d'officine — même
/// calcul partagé que `QuoteLineItemsVentilation` côté devis cabinet (#5091),
/// pour alimenter la même `VentilationBar` côté patient (#8104).
extension PharmacyQuoteItemsVentilation on List<PharmacyQuoteItem> {
  int get amoShareTotalCents =>
      fold(0, (sum, item) => sum + item.amoPartCents);
  int get amcShareTotalCents =>
      fold(0, (sum, item) => sum + item.amcPartCents);
}

/// Devis d'officine (pharmacie → patient), distinct du devis dentaire.
class PharmacyQuote extends Equatable {
  final String id;
  final String pharmacyId;
  final String? pharmacyName;
  final String? patientDisplayName;
  final String? orderId;

  /// Statut courant de la commande d'ancrage (#6820) — un devis `accepted`
  /// peut survivre à une commande devenue `rejected`/`cancelled` (aucun
  /// mécanisme n'expire les devis déjà acceptés, à la différence des devis
  /// `sent`, cf. #6588). `null` si `orderId` est `null`.
  final PharmacyOrderStatus? orderStatus;

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
    this.orderStatus,
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

  /// Devis `accepted` dont la commande d'ancrage a basculé dans un état
  /// terminal sans délivrance (#6820) : il n'y a plus rien à préparer, même
  /// si le devis lui-même reste affiché `accepted` à vie.
  bool get orderIsDeadEnd =>
      orderStatus == PharmacyOrderStatus.rejected ||
      orderStatus == PharmacyOrderStatus.cancelled;

  /// Reste à charge réel (#8104) : `totalCents` moins les parts AMO/AMC déjà
  /// connues ligne à ligne — c'est ce montant, pas `totalCents`, que le
  /// patient engage en acceptant le devis.
  int get patientShareCents =>
      totalCents - items.amoShareTotalCents - items.amcShareTotalCents;

  @override
  List<Object?> get props => [id, status, remindedAt, reminderCount];
}
