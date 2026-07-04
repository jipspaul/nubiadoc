import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Libellé FR d'un statut de commande — unique source du mapping.
String orderStatusLabel(PharmacyOrderStatus status) {
  switch (status) {
    case PharmacyOrderStatus.received:
      return 'Reçue';
    case PharmacyOrderStatus.preparing:
      return 'En préparation';
    case PharmacyOrderStatus.ready:
      return 'Prête';
    case PharmacyOrderStatus.pickedUp:
      return 'Retirée';
    case PharmacyOrderStatus.rejected:
      return 'Refusée';
    case PharmacyOrderStatus.cancelled:
      return 'Annulée';
  }
}

/// Variant sémantique du pill par statut.
StatusPillVariant orderStatusVariant(PharmacyOrderStatus status) {
  switch (status) {
    case PharmacyOrderStatus.received:
      return StatusPillVariant.info;
    case PharmacyOrderStatus.preparing:
      return StatusPillVariant.warning;
    case PharmacyOrderStatus.ready:
      return StatusPillVariant.success;
    case PharmacyOrderStatus.pickedUp:
      return StatusPillVariant.info;
    case PharmacyOrderStatus.rejected:
    case PharmacyOrderStatus.cancelled:
      return StatusPillVariant.error;
  }
}

/// Pill de statut de commande (texte + couleur — jamais la couleur seule, a11y).
class OrderStatusPill extends StatelessWidget {
  const OrderStatusPill({super.key, required this.status});

  final PharmacyOrderStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: orderStatusLabel(status),
      variant: orderStatusVariant(status),
    );
  }
}
