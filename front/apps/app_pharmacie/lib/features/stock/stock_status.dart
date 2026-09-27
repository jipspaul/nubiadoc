import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Mapping statut → libellé/variant d'une demande de stock (design-v2,
/// #6948) — partagé entre [StockTableRow] (widgets/stock_table.dart) et le
/// volet de détail, seuls consommateurs du statut visuel de ce feature.
String stockStatusLabel(StockRequestStatus status) {
  switch (status) {
    case StockRequestStatus.sent:
      return 'Reçue';
    case StockRequestStatus.accepted:
      return 'Acceptée';
    case StockRequestStatus.rejected:
      return 'Refusée';
    case StockRequestStatus.fulfilled:
      return 'Honorée';
    case StockRequestStatus.cancelled:
      return 'Annulée';
  }
}

StatusPillVariant stockStatusVariant(StockRequestStatus status) {
  switch (status) {
    case StockRequestStatus.sent:
      return StatusPillVariant.info;
    case StockRequestStatus.accepted:
      return StatusPillVariant.warning;
    case StockRequestStatus.rejected:
      return StatusPillVariant.error;
    case StockRequestStatus.fulfilled:
      return StatusPillVariant.success;
    // neutral, pas error (#6967) : une annulation vient du cabinet
    // lui-même, ce n'est pas un refus — même token que côté secrétariat.
    case StockRequestStatus.cancelled:
      return StatusPillVariant.neutral;
  }
}
