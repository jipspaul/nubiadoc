// ignore: deprecated_member_use
import 'dart:html' as html;

import 'escape_key_bridge.dart';

EscapeKeyBridge createEscapeKeyBridge(void Function() onEscape) =>
    _WebEscapeKeyBridge(onEscape);

/// Écoute `keydown` sur `document` en phase de CAPTURE (donc avant que
/// l'`<input>` réel de Semantics, qui est plus profond dans l'arbre DOM, ne
/// la reçoive et la consomme) — `stopPropagation` empêche ensuite tout
/// traitement ultérieur (y compris le canal clavier du moteur Flutter), ce
/// qui rend ce pont la seule source de vérité pour Échap sur web (#8512).
class _WebEscapeKeyBridge implements EscapeKeyBridge {
  _WebEscapeKeyBridge(this._onEscape) {
    html.document.addEventListener('keydown', _onKeyDown, true);
  }

  final void Function() _onEscape;

  void _onKeyDown(html.Event event) {
    if (event is! html.KeyboardEvent || event.key != 'Escape') return;
    event.preventDefault();
    event.stopPropagation();
    _onEscape();
  }

  @override
  void dispose() {
    html.document.removeEventListener('keydown', _onKeyDown, true);
  }
}
