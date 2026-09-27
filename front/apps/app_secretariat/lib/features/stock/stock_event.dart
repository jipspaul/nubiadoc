import 'package:nubia_domain/nubia_domain.dart';

abstract class StockEvent {
  const StockEvent();
}

class StockLoadRequested extends StockEvent {
  const StockLoadRequested();
}

class StockCreateRequested extends StockEvent {
  const StockCreateRequested({
    required this.pharmacyId,
    required this.items,
  });

  final String pharmacyId;
  final List<StockRequestItem> items;
}

/// Relance manuelle d'une demande `sent` — le geste quotidien de l'écran
/// Stock (#5183).
class StockResendRequested extends StockEvent {
  const StockResendRequested(this.requestId);

  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is StockResendRequested && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}

/// Annulation d'une demande `sent` partie par erreur (mauvaise officine,
/// mauvaise quantité) — #7818.
class StockCancelRequested extends StockEvent {
  const StockCancelRequested(this.requestId);

  final String requestId;

  @override
  bool operator ==(Object other) =>
      other is StockCancelRequested && other.requestId == requestId;

  @override
  int get hashCode => requestId.hashCode;
}
