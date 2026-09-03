import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_data/nubia_data.dart';
import 'package:nubia_domain/nubia_domain.dart';

/// Fausse connexion WS pilotable (même pattern que
/// ws_pharmacy_order_events_test.dart) : capture les messages sortants et
/// laisse le test injecter les enveloppes serveur.
class _FakeConnection implements WsConnection {
  final controller = StreamController<dynamic>.broadcast();
  final sent = <String>[];

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  void close() {}
}

void main() {
  late _FakeConnection connection;
  late WsClient client;
  late WsNotificationEvents port;

  setUp(() {
    connection = _FakeConnection();
    client = WsClient(
      baseWsUrl: 'ws://test/v1/ws',
      accessTokenProvider: () async => 'token-test',
      channelFactory: (_) => connection,
    );
    port = WsNotificationEvents(client: client);
  });

  tearDown(() => port.dispose());

  test('s\'abonne au canal notifications et mappe les enveloppes', () async {
    final received = <IncomingNotification>[];
    final sub = port.watch().listen(received.add);
    await Future<void>.delayed(Duration.zero);

    expect(
      connection.sent,
      anyElement(allOf(
        contains('"op":"subscribe"'),
        contains('"channel":"notifications"'),
      )),
    );

    connection.controller.add(jsonEncode({
      'channel': 'notifications',
      'event': 'notification_created',
      'data': {
        'id': 'n-1',
        'kind': 'message_received',
        'title': 'Nouveau message reçu',
        'data': {'conversation_id': 'c-9'},
        'created_at': '2026-09-03T10:00:00Z',
      },
    }));
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.id, 'n-1');
    expect(received.single.kind, 'message_received');
    expect(received.single.title, 'Nouveau message reçu');
    expect(received.single.data['conversation_id'], 'c-9');
    await sub.cancel();
  });

  test('ignore les enveloppes d\'autres canaux et les payloads incomplets',
      () async {
    final received = <IncomingNotification>[];
    final sub = port.watch().listen(received.add);
    await Future<void>.delayed(Duration.zero);

    connection.controller.add(jsonEncode({
      'channel': 'pharmacy_orders:x',
      'data': {'id': 'n-2', 'kind': 'k', 'title': 't'},
    }));
    connection.controller.add(jsonEncode({
      'channel': 'notifications',
      'data': {'kind': 'sans_id_ni_titre'},
    }));
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
  });
}
