import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_order_events_port.dart';

/// Signature du fetch de la file complète (vue pharmacie).
typedef FetchOrders = Future<Either<Failure, List<PharmacyOrder>>> Function();

/// Signature du fetch d'une commande (vue patient).
typedef FetchOrder = Future<Either<Failure, PharmacyOrder>> Function(
  String id,
);

/// Implémentation polling du [PharmacyOrderEventsPort] (phase 1).
///
/// Interroge le REST toutes les [interval] (20 s par défaut) et n'émet que
/// sur changement détecté (diff sur `updatedAt`/longueur). Sera remplacée
/// par l'implémentation WebSocket (lot F10) via un simple swap dans le DI —
/// les blocs ne voient que le port.
///
/// Chaque app ne fournit que le fetch de sa vue : [fetchOrders] pour l'app
/// pharmacie, [fetchOrder] pour l'app patient. Appeler un watch sans fetch
/// correspondant est une erreur de câblage DI → [StateError].
class PollingPharmacyOrderEvents implements PharmacyOrderEventsPort {
  final FetchOrders? fetchOrders;
  final FetchOrder? fetchOrder;
  final Duration interval;

  final List<Timer> _timers = [];

  PollingPharmacyOrderEvents({
    this.fetchOrders,
    this.fetchOrder,
    this.interval = const Duration(seconds: 20),
  });

  @override
  Stream<List<PharmacyOrder>> watchOrders() {
    final fetch = fetchOrders;
    if (fetch == null) {
      throw StateError(
        'watchOrders() sans fetchOrders — DI incomplet pour cette app.',
      );
    }

    late StreamController<List<PharmacyOrder>> controller;
    Timer? timer;
    var lastSignature = '';

    Future<void> poll() async {
      final result = await fetch();
      result.fold((_) {}, (orders) {
        final signature = _ordersSignature(orders);
        if (signature != lastSignature && !controller.isClosed) {
          lastSignature = signature;
          controller.add(orders);
        }
      });
    }

    controller = StreamController<List<PharmacyOrder>>(
      onListen: () {
        poll();
        timer = Timer.periodic(interval, (_) => poll());
        _timers.add(timer!);
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  @override
  Stream<PharmacyOrder> watchOrder(String id) {
    final fetch = fetchOrder;
    if (fetch == null) {
      throw StateError(
        'watchOrder() sans fetchOrder — DI incomplet pour cette app.',
      );
    }

    late StreamController<PharmacyOrder> controller;
    Timer? timer;
    PharmacyOrder? last;

    Future<void> poll() async {
      final result = await fetch(id);
      result.fold((_) {}, (order) {
        if (order != last && !controller.isClosed) {
          last = order;
          controller.add(order);
        }
      });
    }

    controller = StreamController<PharmacyOrder>(
      onListen: () {
        poll();
        timer = Timer.periodic(interval, (_) => poll());
        _timers.add(timer!);
      },
      onCancel: () => timer?.cancel(),
    );
    return controller.stream;
  }

  static String _ordersSignature(List<PharmacyOrder> orders) => orders
      .map((o) => '${o.id}:${o.status.name}:${o.updatedAt.toIso8601String()}')
      .join('|');

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}
