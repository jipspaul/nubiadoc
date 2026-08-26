import 'package:equatable/equatable.dart';

enum QuoteStatus { draft, sent, signed, expired, cancelled }

/// Classification 100% Santé d'un acte (`ccam_act.panier_sante`, #4055).
/// `null`/[unknown] si la ligne n'a pas de code CCAM ou n'est pas encore
/// classifiée : ne JAMAIS déduire `rac0` par défaut d'une valeur absente
/// (obligation conventionnelle de présenter l'alternative RAC 0, #4061).
enum PanierSante {
  rac0,
  modere,
  libre,
  horsNomenclature,
  unknown;

  static PanierSante fromApi(String? raw) => switch (raw) {
        'rac0' => PanierSante.rac0,
        'modere' => PanierSante.modere,
        'libre' => PanierSante.libre,
        'hors_nomenclature' => PanierSante.horsNomenclature,
        _ => PanierSante.unknown,
      };
}

class QuoteLineItem extends Equatable {
  final String id;
  final String label;
  final String? ccamCode;
  final String? toothLabel; // e.g. "11", "46"
  final int totalCents;
  final int amoShareCents; // Remboursement Sécu
  final int amcShareCents; // Remboursement Mutuelle
  final int patientShareCents; // Reste à charge
  final PanierSante panierSante;

  const QuoteLineItem({
    required this.id,
    required this.label,
    this.ccamCode,
    this.toothLabel,
    required this.totalCents,
    required this.amoShareCents,
    required this.amcShareCents,
    required this.patientShareCents,
    this.panierSante = PanierSante.unknown,
  });

  @override
  List<Object?> get props => [id];
}

/// Agrégation AMO/AMC d'une liste de lignes de devis — calcul partagé entre
/// l'app Patient et l'app Secrétariat pour la ventilation du volet détail
/// (#5091) : mêmes montants, pas de formule dupliquée par app.
extension QuoteLineItemsVentilation on List<QuoteLineItem> {
  int get amoShareTotalCents =>
      fold(0, (sum, item) => sum + item.amoShareCents);
  int get amcShareTotalCents =>
      fold(0, (sum, item) => sum + item.amcShareCents);
}

class Quote extends Equatable {
  final String id;
  final String cabinetId;
  final String practitionerName;
  final List<QuoteLineItem> items;
  final int totalCents;
  final int patientShareCents; // total reste à charge
  final int depositCents; // acompte demandé
  final QuoteStatus status;
  final DateTime createdAt;
  final DateTime? signedAt;
  final DateTime? expiresAt;
  final String? documentId; // signed PDF in vault

  const Quote({
    required this.id,
    required this.cabinetId,
    required this.practitionerName,
    required this.items,
    required this.totalCents,
    required this.patientShareCents,
    required this.depositCents,
    required this.status,
    required this.createdAt,
    this.signedAt,
    this.expiresAt,
    this.documentId,
  });

  bool get canSign => status == QuoteStatus.sent;
  bool get isExpired => expiresAt?.isBefore(DateTime.now()) ?? false;

  @override
  List<Object?> get props => [id, status];
}
