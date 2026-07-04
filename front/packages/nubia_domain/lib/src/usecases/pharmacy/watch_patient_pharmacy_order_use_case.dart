import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/repositories/pharmacy_order_events_port.dart';

/// Flux temps réel d'une commande (vue patient).
class WatchPatientPharmacyOrderUseCase {
  final PharmacyOrderEventsPort _events;

  const WatchPatientPharmacyOrderUseCase(this._events);

  Stream<PharmacyOrder> call(String orderId) => _events.watchOrder(orderId);
}
