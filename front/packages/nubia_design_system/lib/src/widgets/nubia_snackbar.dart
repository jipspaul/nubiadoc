// lib/presentation/widgets/nubia_snackbar.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Variants sémantiques du [NubiaSnackbar].
enum NubiaSnackbarVariant {
  /// Information neutre (bleu/cyan).
  info,

  /// Succès (vert).
  success,

  /// Erreur/danger (rouge).
  error,
}

/// Helper d'affichage d'un snackbar / toast Nubia en bas d'écran.
///
/// [NubiaSnackbar.show] affiche un snackbar flottant (radius `md` = 8) avec
/// icône + texte colorés selon la [NubiaSnackbarVariant]. Auto-dismiss après
/// 4 s, ou 6 s lorsqu'une action est fournie.
///
/// - [message] : texte affiché.
/// - [variant] : `info` / `success` / `error` (défaut `info`).
/// - [actionLabel] + [onAction] : action optionnelle (allonge à 6 s).
///
/// Réfs : `DESIGN-TARGET-SYNTHESIS.md` §3 (Snackbar/Toast) ; couleurs
/// sémantiques via [NubiaTokens].
class NubiaSnackbar {
  const NubiaSnackbar._();

  /// Affiche le snackbar et renvoie le contrôleur `ScaffoldMessenger`.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show({
    required BuildContext context,
    required String message,
    NubiaSnackbarVariant variant = NubiaSnackbarVariant.info,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final bool hasAction = actionLabel != null && onAction != null;

    final Color bg;
    final Color fg;
    final IconData icon;
    switch (variant) {
      case NubiaSnackbarVariant.info:
        bg = tokens.infoBg;
        fg = tokens.infoFg;
        icon = Icons.info_outline;
      case NubiaSnackbarVariant.success:
        bg = tokens.successBg;
        fg = tokens.successFg;
        icon = Icons.check_circle_outline;
      case NubiaSnackbarVariant.error:
        bg = tokens.dangerBg;
        fg = tokens.dangerFg;
        icon = Icons.error_outline;
    }

    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: hasAction ? 6 : 4),
      backgroundColor: bg,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      content: Row(
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
      action: hasAction
          ? SnackBarAction(
              label: actionLabel,
              textColor: fg,
              onPressed: onAction,
            )
          : null,
    );

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    return messenger.showSnackBar(snackBar);
  }
}
