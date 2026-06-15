import '../messages/a2ui_message.dart';

/// Bidirectional A2UI transport. Implementations stream server messages and
/// send client events. JWT auth (from nubia_core TokenStorage) is injected as
/// the `Authorization` header by the concrete transports.
abstract class A2uiTransport {
  /// Connects and returns the inbound message stream.
  Stream<A2uiMessage> connect(Uri endpoint, {Map<String, String>? headers});

  /// Sends a client event (action/RPC) to the server.
  Future<void> send(A2uiClientEvent event);

  Future<void> close();
}

/// A transport backed by an in-memory message stream — used for demos, golden
/// tests, and driving a surface from a local fixture without any server.
class FixtureTransport implements A2uiTransport {
  FixtureTransport(this._messages);

  final Stream<A2uiMessage> _messages;
  final List<A2uiClientEvent> sentEvents = [];

  @override
  Stream<A2uiMessage> connect(Uri endpoint, {Map<String, String>? headers}) =>
      _messages;

  @override
  Future<void> send(A2uiClientEvent event) async => sentEvents.add(event);

  @override
  Future<void> close() async {}
}
