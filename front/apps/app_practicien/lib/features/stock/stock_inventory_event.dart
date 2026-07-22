abstract class StockInventoryEvent {
  const StockInventoryEvent();
}

class StockInventoryLoadRequested extends StockInventoryEvent {
  const StockInventoryLoadRequested();
}

class StockInventoryMovementRequested extends StockInventoryEvent {
  const StockInventoryMovementRequested({
    required this.itemId,
    required this.delta,
    required this.reason,
  });

  final String itemId;
  final int delta;
  final String reason;
}
