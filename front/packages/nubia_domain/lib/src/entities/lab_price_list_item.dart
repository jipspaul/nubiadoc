import 'package:equatable/equatable.dart';

/// Une ligne de la grille tarifaire d'un laboratoire (#7163, DP-F19.c).
/// Source : `GET /v1/cabinet/lab-price-list` — sert à pré-remplir le prix
/// d'achat quand un produit de la grille est sélectionné à la commande.
class LabPriceListItem extends Equatable {
  final String id;
  final String labName;
  final String itemLabel;
  final String itemCode;
  final int priceCents;
  final String validFrom;

  const LabPriceListItem({
    required this.id,
    required this.labName,
    required this.itemLabel,
    required this.itemCode,
    required this.priceCents,
    required this.validFrom,
  });

  @override
  List<Object?> get props => [id, labName, itemLabel, itemCode, priceCents, validFrom];
}
