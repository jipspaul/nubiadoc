import '../messages/a2ui_message.dart';
import '../transport/a2ui_transport.dart';

/// Routes component actions either to a local handler or back to the server.
///
/// An action [ref] is either a string (the action/function name) or an inline
/// map `{"action": "name", "args": {...}}`. Local handlers registered via
/// [onLocal] take precedence; anything else is sent over the [transport].
class A2uiActionDispatcher {
  A2uiActionDispatcher({A2uiTransport? transport, this.onLocal})
      : _transport = transport;

  final A2uiTransport? _transport;

  /// Optional local handler; return true if the action was handled locally.
  final bool Function(String surfaceId, String action, Map<String, dynamic> args)?
      onLocal;

  void dispatch(String surfaceId, Object ref, Map<String, dynamic> args) {
    final (name, inlineArgs) = _parse(ref);
    final merged = {...inlineArgs, ...args};
    if (onLocal?.call(surfaceId, name, merged) ?? false) return;
    _transport?.send(
      A2uiClientEvent(surfaceId: surfaceId, action: name, args: merged),
    );
  }

  (String, Map<String, dynamic>) _parse(Object ref) {
    if (ref is String) return (ref, const {});
    if (ref is Map) {
      final name = (ref['action'] ?? ref['name'] ?? '').toString();
      final args = (ref['args'] as Map?)?.cast<String, dynamic>() ?? const {};
      return (name, args);
    }
    return (ref.toString(), const {});
  }
}
