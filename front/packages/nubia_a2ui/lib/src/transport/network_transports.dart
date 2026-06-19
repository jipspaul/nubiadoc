import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../messages/a2ui_message.dart';
import 'a2ui_transport.dart';

/// WebSocket transport (a2ui.org bidirectional sessions).
///
/// Skeleton: wiring is in place (connect/encode/decode) but not yet covered by
/// integration tests against a live A2UI server.
class WebSocketTransport implements A2uiTransport {
  WebSocketChannel? _channel;

  @override
  Stream<A2uiMessage> connect(Uri endpoint, {Map<String, String>? headers}) {
    final channel = WebSocketChannel.connect(endpoint);
    _channel = channel;
    return channel.stream.map((event) {
      final json = jsonDecode(event as String) as Map<String, dynamic>;
      return A2uiMessage.fromJson(json);
    });
  }

  @override
  Future<void> send(A2uiClientEvent event) async {
    _channel?.sink.add(jsonEncode(event.toJson()));
  }

  @override
  Future<void> close() async {
    await _channel?.sink.close();
  }
}

/// Server-Sent-Events transport (server → client only).
///
/// Stub: returns an empty stream until wired to an HTTP streaming client
/// (e.g. Dio response stream) with the JWT auth header. Client events are
/// expected to use a companion POST endpoint.
class SseTransport implements A2uiTransport {
  @override
  Stream<A2uiMessage> connect(Uri endpoint, {Map<String, String>? headers}) {
    // TODO(nubia): stream `endpoint` via Dio with Authorization header and
    // parse each `data:` line through A2uiMessage.fromJson.
    return const Stream.empty();
  }

  @override
  Future<void> send(A2uiClientEvent event) async {
    // TODO(nubia): POST the event to the companion action endpoint.
  }

  @override
  Future<void> close() async {}
}
