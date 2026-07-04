import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/repositories/pharmacy_order_events_port.dart';

/// Flux temps réel de la file de commandes (vue pharmacie).
class WatchPharmacyOrdersUseCase {
  final PharmacyOrderEventsPort _events;

  const WatchPharmacyOrdersUseCase(this._events);

  Stream<List<PharmacyOrder>> call() => _events.watchOrders();
}
