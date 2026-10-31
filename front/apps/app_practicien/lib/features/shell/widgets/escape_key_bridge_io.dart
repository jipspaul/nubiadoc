import 'escape_key_bridge.dart';

EscapeKeyBridge createEscapeKeyBridge(void Function() onEscape) =>
    _NoopEscapeKeyBridge();

/// Hors web : le `Focus` ancêtre de `global_search_dialog.dart` reçoit déjà
/// Échap nativement, sans la couche DOM/Semantics propre au web (#8512).
class _NoopEscapeKeyBridge implements EscapeKeyBridge {
  @override
  void dispose() {}
}
