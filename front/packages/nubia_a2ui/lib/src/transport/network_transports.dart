import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

/// HTTP interface for opening SSE connections — injectable and testable.
abstract class SseHttpClient {
  /// Opens a GET to [uri] with [headers] and yields response body lines.
  Stream<String> getLines(Uri uri, Map<String, String> headers);
}

/// dart:io backed production [SseHttpClient].
class IoSseHttpClient implements SseHttpClient {
  const IoSseHttpClient();

  @override
  Stream<String> getLines(Uri uri, Map<String, String> headers) async* {
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      headers.forEach((k, v) => request.headers.set(k, v));
      request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
      final response = await request.close();
      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        yield line;
      }
    } finally {
      client.close();
    }
  }
}

/// Server-Sent Events transport (server → client).
///
/// Connects to [endpoint] with `Authorization: Bearer [_authToken]`, parses
/// `data: <json>` lines into [A2uiMessage]s, and reconnects with exponential
/// backoff (1 s → 30 s max) on disconnection.
class SseTransport implements A2uiTransport {
  SseTransport(this._http, this._authToken);

  final SseHttpClient _http;
  final String _authToken;
  bool _closed = false;

  static const _minDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 30);

  @override
  Stream<A2uiMessage> connect(Uri endpoint, {Map<String, String>? headers}) =>
      _stream(endpoint, headers ?? const {});

  Stream<A2uiMessage> _stream(
    Uri endpoint,
    Map<String, String> extraHeaders,
  ) async* {
    var delay = _minDelay;
    while (!_closed) {
      final allHeaders = {
        'Authorization': 'Bearer $_authToken',
        ...extraHeaders,
      };
      var gotEvent = false;
      try {
        await for (final line in _http.getLines(endpoint, allHeaders)) {
          if (_closed) return;
          if (line.startsWith('data:')) {
            final payload = line.substring(5).trim();
            if (payload.isNotEmpty) {
              try {
                final json = jsonDecode(payload) as Map<String, dynamic>;
                yield A2uiMessage.fromJson(json);
                gotEvent = true;
              } catch (_) {
                // malformed payload — skip
              }
            }
          }
        }
      } catch (_) {
        // connection error — fall through to reconnect
      }
      if (gotEvent) delay = _minDelay;
      if (_closed) return;
      await Future<void>.delayed(delay);
      delay = Duration(
        milliseconds:
            math.min(delay.inMilliseconds * 2, _maxDelay.inMilliseconds),
      );
    }
  }

  @override
  Future<void> send(A2uiClientEvent event) async {
    // SSE is server→client only; client actions use a companion POST endpoint.
  }

  @override
  Future<void> close() async => _closed = true;
}
