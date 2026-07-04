import 'dart:async';
import 'dart:convert';

import 'package:nubia_domain/nubia_domain.dart';

import 'polling_pharmacy_order_events.dart';
import 'ws_client.dart';

/// Extrait un claim du payload JWT (décodage local, sans vérification —
/// le serveur reste l'autorité, on ne s'en sert que pour nommer le canal).
String? jwtClaim(String token, String claim) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[1])),
    );
    final map = jsonDecode(payload);
    if (map is! Map<String, dynamic>) return null;
    final value = map[claim];
    return value is String ? value : null;
  } catch (_) {
    return null;
  }
}

/// Implémentation WebSocket du [PharmacyOrderEventsPort] (lot F10).
///
/// À chaque événement `order_status_changed` reçu sur le canal, l'impl
/// re-fetch le REST (source of truth) et émet — même contrat que le polling.
/// En cas d'échec WS (pas de token, connexion impossible), retombe sur le
/// [fallback] polling : les blocs ne voient aucune différence.
class WsPharmacyOrderEvents implements PharmacyOrderEventsPort {
  WsPharmacyOrderEvents({
    required WsClient client,
    required Future<String?> Function() accessTokenProvider,
    required PollingPharmacyOrderEvents fallback,
    FetchOrders? fetchOrders,
    FetchOrder? fetchOrder,
  })  : _client = client,
        _accessToken = accessTokenProvider,
        _fallback = fallback,
        _fetchOrders = fetchOrders,
        _fetchOrder = fetchOrder;

  final WsClient _client;
  final Future<String?> Function() _accessToken;
  final PollingPharmacyOrderEvents _fallback;
  final FetchOrders? _fetchOrders;
  final FetchOrder? _fetchOrder;

  @override
  Stream<List<PharmacyOrder>> watchOrders() {
    final fetch = _fetchOrders;
    if (fetch == null) {
      throw StateError('watchOrders() sans fetchOrders — DI incomplet.');
    }

    late StreamController<List<PharmacyOrder>> controller;
    StreamSubscription<Map<String, dynamic>>? wsSubscription;
    StreamSubscription<List<PharmacyOrder>>? fallbackSubscription;

    Future<void> refetch() async {
      final result = await fetch();
      result.fold((_) {}, (orders) {
        if (!controller.isClosed) controller.add(orders);
      });
    }

    controller = StreamController<List<PharmacyOrder>>(
      onListen: () async {
        final token = await _accessToken();
        final pharmacyId =
            token == null ? null : jwtClaim(token, 'pharmacy_id');
        if (pharmacyId == null) {
          // Pas de contexte pharmacie → polling.
          fallbackSubscription = _fallback.watchOrders().listen(
                controller.add,
                onError: (_) {},
              );
          return;
        }
        try {
          await _client.subscribe('pharmacy_orders:$pharmacyId');
          await refetch();
          wsSubscription = _client.events.listen((envelope) {
            if (envelope['channel'] == 'pharmacy_orders:$pharmacyId') {
              refetch();
            }
          });
        } catch (_) {
          fallbackSubscription = _fallback.watchOrders().listen(
                controller.add,
                onError: (_) {},
              );
        }
      },
      onCancel: () {
        wsSubscription?.cancel();
        fallbackSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Stream<PharmacyOrder> watchOrder(String id) {
    final fetch = _fetchOrder;
    if (fetch == null) {
      throw StateError('watchOrder() sans fetchOrder — DI incomplet.');
    }

    late StreamController<PharmacyOrder> controller;
    StreamSubscription<Map<String, dynamic>>? wsSubscription;
    StreamSubscription<PharmacyOrder>? fallbackSubscription;
    PharmacyOrder? last;

    Future<void> refetch() async {
      final result = await fetch(id);
      result.fold((_) {}, (order) {
        if (order != last && !controller.isClosed) {
          last = order;
          controller.add(order);
        }
      });
    }

    controller = StreamController<PharmacyOrder>(
      onListen: () async {
        final token = await _accessToken();
        final accountId = token == null ? null : jwtClaim(token, 'account_id');
        if (accountId == null) {
          fallbackSubscription = _fallback.watchOrder(id).listen(
                controller.add,
                onError: (_) {},
              );
          return;
        }
        try {
          await _client.subscribe('account_orders:$accountId');
          await refetch();
          wsSubscription = _client.events.listen((envelope) {
            final data = envelope['data'];
            final matches =
                envelope['channel'] == 'account_orders:$accountId' &&
                    data is Map<String, dynamic> &&
                    data['order_id'] == id;
            if (matches) refetch();
          });
        } catch (_) {
          fallbackSubscription = _fallback.watchOrder(id).listen(
                controller.add,
                onError: (_) {},
              );
        }
      },
      onCancel: () {
        wsSubscription?.cancel();
        fallbackSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  void dispose() {
    _client.dispose();
    _fallback.dispose();
  }
}
