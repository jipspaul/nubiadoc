import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

PharmacyOrder order(String id, PharmacyOrderStatus status, int minute) =>
    PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      prescriptionId: 'rx1',
      status: status,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1, 10, minute),
    );

class FakeConnection implements WsConnection {
  FakeConnection(this.incoming);

  final StreamController<dynamic> incoming;
  final sent = <String>[];

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  void close() {}
}

/// JWT non signé (header.payload.signature) — le décodage local ne vérifie pas.
String fakeJwt(Map<String, dynamic> claims) {
  String b64(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${b64({"alg": "HS256"})}.${b64(claims)}.sig';
}

void main() {
  group('jwtClaim', () {
    test('extrait pharmacy_id / account_id du payload', () {
      final token = fakeJwt({'kind': 'pharma', 'pharmacy_id': 'p-42'});
      expect(jwtClaim(token, 'pharmacy_id'), 'p-42');
      expect(jwtClaim(token, 'account_id'), isNull);
      expect(jwtClaim('pas-un-jwt', 'pharmacy_id'), isNull);
    });
  });

  group('WsClient', () {
    test('décode les enveloppes et resubscribe est envoyé à la connexion',
        () async {
      final incoming = StreamController<dynamic>();
      final connection = FakeConnection(incoming);

      final client = WsClient(
        baseWsUrl: 'ws://test/v1/ws',
        accessTokenProvider: () async => fakeJwt({'pharmacy_id': 'p1'}),
        channelFactory: (_) => connection,
      );

      final received = <Map<String, dynamic>>[];
      client.events.listen(received.add);
      await client.subscribe('pharmacy_orders:p1');
      await Future<void>.delayed(Duration.zero);

      expect(connection.sent, hasLength(1));
      expect(
          jsonDecode(connection.sent.first)['channel'], 'pharmacy_orders:p1');

      incoming.add(jsonEncode({
        'channel': 'pharmacy_orders:p1',
        'event': 'order_status_changed',
        'data': {'order_id': 'o1', 'status': 'preparing'},
      }));
      incoming.add('pas du json'); // ignoré sans crash
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.first['event'], 'order_status_changed');
      client.dispose();
    });
  });

  group('WsPharmacyOrderEvents', () {
    test('un événement sur le canal déclenche un re-fetch REST', () async {
      final incoming = StreamController<dynamic>();
      var fetches = 0;
      final responses = [
        [order('o1', PharmacyOrderStatus.received, 0)],
        [order('o1', PharmacyOrderStatus.preparing, 5)],
      ];

      final events = WsPharmacyOrderEvents(
        client: WsClient(
          baseWsUrl: 'ws://test/v1/ws',
          accessTokenProvider: () async => fakeJwt({'pharmacy_id': 'p1'}),
          channelFactory: (_) => FakeConnection(incoming),
        ),
        accessTokenProvider: () async => fakeJwt({'pharmacy_id': 'p1'}),
        fallback: PollingPharmacyOrderEvents(
          fetchOrders: () async => const Right([]),
        ),
        fetchOrders: () async {
          final index = fetches < responses.length ? fetches : 1;
          fetches++;
          return Right(responses[index]);
        },
      );

      final emitted = <List<PharmacyOrder>>[];
      final subscription = events.watchOrders().listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      incoming.add(jsonEncode({
        'channel': 'pharmacy_orders:p1',
        'event': 'order_status_changed',
        'data': {'order_id': 'o1', 'status': 'preparing'},
      }));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(emitted, hasLength(2), reason: 'fetch initial + re-fetch');
      expect(emitted.last.single.status, PharmacyOrderStatus.preparing);
      await subscription.cancel();
      events.dispose();
    });

    test('sans contexte pharmacie dans le token → fallback polling', () async {
      final events = WsPharmacyOrderEvents(
        client: WsClient(
          baseWsUrl: 'ws://test/v1/ws',
          accessTokenProvider: () async => fakeJwt({'kind': 'patient'}),
        ),
        accessTokenProvider: () async => fakeJwt({'kind': 'patient'}),
        fallback: PollingPharmacyOrderEvents(
          interval: const Duration(milliseconds: 20),
          fetchOrders: () async =>
              Right([order('o9', PharmacyOrderStatus.ready, 0)]),
        ),
        fetchOrders: () async => const Right([]),
      );

      final emitted = <List<PharmacyOrder>>[];
      final subscription = events.watchOrders().listen(emitted.add);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(emitted, isNotEmpty, reason: 'le polling a pris le relais');
      expect(emitted.first.single.id, 'o9');
      await subscription.cancel();
      events.dispose();
    });
  });
}
