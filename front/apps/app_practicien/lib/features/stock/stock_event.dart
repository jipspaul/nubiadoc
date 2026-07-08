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
