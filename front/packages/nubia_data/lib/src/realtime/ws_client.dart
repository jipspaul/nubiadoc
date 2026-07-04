import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Connexion WebSocket minimale — abstraction testable au-dessus de
/// [WebSocketChannel].
abstract class WsConnection {
  Stream<dynamic> get stream;
  void send(String message);
  void close();
}

class _ChannelConnection implements WsConnection {
  _ChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Stream<dynamic> get stream => _channel.stream;

  @override
  void send(String message) => _channel.sink.add(message);

  @override
  void close() => _channel.sink.close();
}

/// Fabrique de connexion — injectable pour les tests.
typedef WsChannelFactory = WsConnection Function(Uri uri);

WsConnection _defaultConnect(Uri uri) =>
    _ChannelConnection(WebSocketChannel.connect(uri));

/// Client WebSocket `GET /v1/ws` : subscribe par canal, enveloppes
/// `{channel, event, data, ts}`, reconnexion avec backoff exponentiel.
///
/// Le contrat serveur (docs/12 §20) : envoyer
/// `{"op":"subscribe","channel":"…"}` après connexion ; l'auth passe par
/// `?access_token=`.
class WsClient {
  WsClient({
    required this.baseWsUrl,
    required Future<String?> Function() accessTokenProvider,
    WsChannelFactory? channelFactory,
  })  : _accessToken = accessTokenProvider,
        _channelFactory = channelFactory ?? _defaultConnect;

  /// ws(s)://…/v1/ws — dérivé de l'API base URL.
  final String baseWsUrl;
  final Future<String?> Function() _accessToken;
  final WsChannelFactory _channelFactory;

  WsConnection? _channel;
  StreamSubscription<dynamic>? _subscription;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _channels = <String>{};
  int _retries = 0;
  bool _disposed = false;

  /// Enveloppes serveur décodées, tous canaux confondus.
  Stream<Map<String, dynamic>> get events => _events.stream;

  /// S'abonne à [channel] (connecte à la demande, re-subscribe après
  /// reconnexion).
  Future<void> subscribe(String channel) async {
    _channels.add(channel);
    await _ensureConnected();
    _send({'op': 'subscribe', 'channel': channel});
  }

  Future<void> _ensureConnected() async {
    if (_channel != null || _disposed) return;
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      throw StateError('ws: pas de token d\'accès');
    }
    final uri = Uri.parse('$baseWsUrl?access_token=$token');
    final connection = _channelFactory(uri);
    _channel = connection;
    _subscription = connection.stream.listen(
      (raw) {
        _retries = 0;
        final decoded = _decode(raw);
        if (decoded != null && !_events.isClosed) {
          _events.add(decoded);
        }
      },
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    if (raw is! String) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic> ? value : null;
    } catch (_) {
      return null;
    }
  }

  void _send(Map<String, dynamic> message) {
    _channel?.send(jsonEncode(message));
  }

  void _scheduleReconnect() {
    _subscription?.cancel();
    _subscription = null;
    _channel = null;
    if (_disposed || _channels.isEmpty) return;
    // Backoff exponentiel plafonné à 30 s.
    final delay = Duration(seconds: (1 << _retries.clamp(0, 5)));
    _retries++;
    Timer(delay, () async {
      if (_disposed) return;
      try {
        await _ensureConnected();
        for (final channel in _channels) {
          _send({'op': 'subscribe', 'channel': channel});
        }
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _channel?.close();
    _events.close();
  }
}
