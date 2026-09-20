abstract class StockLocationsEvent {
  const StockLocationsEvent();
}

class StockLocationsLoadRequested extends StockLocationsEvent {
  const StockLocationsLoadRequested();
}

class StockLocationsCreateRequested extends StockLocationsEvent {
  const StockLocationsCreateRequested(this.name);

  final String name;
}

class StockLocationsDeleteRequested extends StockLocationsEvent {
  const StockLocationsDeleteRequested(this.locationId);

  final String locationId;
}

class StockLocationsTransferRequested extends StockLocationsEvent {
  const StockLocationsTransferRequested({
    required this.itemId,
    required this.fromLocationId,
    required this.toLocationId,
    required this.quantity,
  });

  final String itemId;
  final String fromLocationId;
  final String toLocationId;
  final int quantity;
}

class StockLocationsThresholdRequested extends StockLocationsEvent {
  const StockLocationsThresholdRequested({
    required this.itemId,
    required this.locationId,
    required this.threshold,
  });

  final String itemId;
  final String locationId;

  /// `null` efface le seuil.
  final int? threshold;
}
