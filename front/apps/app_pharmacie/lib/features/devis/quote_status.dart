import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Mapping statut → libellé/variant/icône du devis d'officine (design-v2,
/// #6454) — partagé entre [DevisTableRow] et le volet de détail, seuls
/// consommateurs du statut visuel de ce feature.
String quoteStatusLabel(PharmacyQuoteStatus status) {
  switch (status) {
    case PharmacyQuoteStatus.draft:
      return 'Brouillon';
    case PharmacyQuoteStatus.sent:
      return 'Envoyé';
    case PharmacyQuoteStatus.accepted:
      return 'Accepté';
    case PharmacyQuoteStatus.refused:
      return 'Refusé';
    case PharmacyQuoteStatus.expired:
      return 'Expiré';
  }
}

StatusPillVariant quoteStatusVariant(PharmacyQuoteStatus status) {
  switch (status) {
    case PharmacyQuoteStatus.draft:
      return StatusPillVariant.info;
    case PharmacyQuoteStatus.sent:
      return StatusPillVariant.warning;
    case PharmacyQuoteStatus.accepted:
      return StatusPillVariant.success;
    case PharmacyQuoteStatus.refused:
    case PharmacyQuoteStatus.expired:
      return StatusPillVariant.error;
  }
}

/// `refused` et `expired` partagent le variant `error` : seule l'icône
/// distingue les deux — un refus est une décision du patient, une
/// expiration un délai dépassé.
IconData? quoteStatusIcon(PharmacyQuoteStatus status) {
  switch (status) {
    case PharmacyQuoteStatus.refused:
      return Icons.cancel;
    case PharmacyQuoteStatus.expired:
      return Icons.event_busy;
    case PharmacyQuoteStatus.draft:
    case PharmacyQuoteStatus.sent:
    case PharmacyQuoteStatus.accepted:
      return null;
  }
}
