import 'escape_key_bridge_io.dart' if (dart.library.html) 'escape_key_bridge_web.dart'
    as impl;

/// Pont DOM pour Échap (#8512) : quand l'arbre Semantics est actif sur web,
/// l'édition de texte passe par un `<input>` réel du DOM placé dans
/// `flt-semantics` (cf. `flt-text-editing-stylesheet`), qui consomme le
/// `keydown` Échap avant qu'il ne soit réinjecté dans l'arbre `Focus`
/// Flutter — le `Focus` ancêtre de `global_search_dialog.dart` (#8300) ne le
/// voit alors jamais. On intercepte donc Échap en amont, en phase de
/// capture sur `document` (donc avant que cet `<input>` ne le reçoive),
/// en complément du `Focus` ancêtre qui reste la voie native (non-web) et le
/// filet de sécurité web hors Semantics. No-op hors web.
abstract class EscapeKeyBridge {
  void dispose();
}

EscapeKeyBridge createEscapeKeyBridge(void Function() onEscape) =>
    impl.createEscapeKeyBridge(onEscape);
