// lib/presentation/widgets/nubia_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Helper d'ouverture + conteneur du bottom sheet / modal Nubia.
///
/// [NubiaBottomSheet.show] ouvre une feuille modale glissant depuis le bas
/// (~240 ms), scrim ~45 %, radius `xl` (16) en haut, poignée (handle) 32×4 et
/// padding 16. Dismissible par défaut (tap sur le scrim + glissé vers le bas).
///
/// - [child] : contenu de la feuille (sous la poignée).
/// - [isDismissible] : autorise la fermeture par scrim + drag (défaut `true`).
/// - [showHandle] : affiche la poignée en haut (défaut `true`).
///
/// Réfs mockup : `design/mockups/lib/screens-wedge.jsx` (feuilles WEDGE) ;
/// tokens radius `--r-xl` (16), scrim 45 %.
class NubiaBottomSheet {
  const NubiaBottomSheet._();

  /// Ouvre une feuille modale Nubia contenant [child] et renvoie la valeur
  /// éventuellement passée à `Navigator.pop`.
  static Future<T?> show<T>({
    required BuildContext context,
    required Widget child,
    bool isDismissible = true,
    bool showHandle = true,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 240),
        reverseDuration: Duration(milliseconds: 240),
      ),
      builder: (_) =>
          _NubiaBottomSheetContainer(showHandle: showHandle, child: child),
    );
  }

  /// Variante « page » de [show] : à utiliser quand la feuille doit porter
  /// sa propre entrée d'historique (ex. `pageBuilder` d'une `GoRoute`) au
  /// lieu d'être poussée directement sur le `Navigator` — [show] ne crée
  /// aucune entrée d'historique web, donc sous go_router le retour
  /// navigateur ne voit rien à dépiler pour la feuille et saute directement
  /// à la route précédente (#7803). Même rendu (radius, poignée, scrim,
  /// durée d'animation) que [show].
  static Page<T> page<T>({
    required WidgetBuilder builder,
    LocalKey? key,
    bool isDismissible = true,
    bool showHandle = true,
  }) {
    return _NubiaBottomSheetPage<T>(
      key: key,
      builder: builder,
      isDismissible: isDismissible,
      showHandle: showHandle,
    );
  }
}

class _NubiaBottomSheetPage<T> extends Page<T> {
  const _NubiaBottomSheetPage({
    required this.builder,
    super.key,
    this.isDismissible = true,
    this.showHandle = true,
  });

  final WidgetBuilder builder;
  final bool isDismissible;
  final bool showHandle;

  @override
  Route<T> createRoute(BuildContext context) {
    return ModalBottomSheetRoute<T>(
      settings: this,
      isScrollControlled: true,
      isDismissible: isDismissible,
      enableDrag: isDismissible,
      backgroundColor: Colors.transparent,
      modalBarrierColor: Colors.black.withValues(alpha: 0.45),
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 240),
        reverseDuration: Duration(milliseconds: 240),
      ),
      builder: (context) => _NubiaBottomSheetContainer(
        showHandle: showHandle,
        child: Builder(builder: builder),
      ),
    );
  }
}

/// Conteneur visuel de la feuille : radius `xl` en haut, poignée, padding 16.
class _NubiaBottomSheetContainer extends StatelessWidget {
  const _NubiaBottomSheetContainer({
    required this.child,
    this.showHandle = true,
  });

  final Widget child;
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showHandle) ...[
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.borderDefault,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}
