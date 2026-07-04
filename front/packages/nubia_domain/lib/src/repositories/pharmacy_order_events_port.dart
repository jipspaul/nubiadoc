import 'package:nubia_domain/src/entities/pharmacy_order.dart';

/// Flux temps réel des commandes click-and-collect.
///
/// Port framework-free (dart:core Streams). Implémentations côté data :
/// polling (phase 1) puis WebSocket /v1/ws (phase 2) — swap invisible
/// pour les blocs.
abstract class PharmacyOrderEventsPort {
  /// Toutes les commandes de la pharmacie courante (vue pharmacie).
  /// Émet une nouvelle liste à chaque changement détecté.
  Stream<List<PharmacyOrder>> watchOrders();

  /// Une commande précise (vue patient). Émet à chaque changement de statut.
  Stream<PharmacyOrder> watchOrder(String id);

  /// Libère les ressources (timers, sockets).
  void dispose();
}
