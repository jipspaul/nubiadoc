// lib/presentation/widgets/nubia_badge.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Variants sémantiques du [NubiaBadge].
enum NubiaBadgeVariant {
  /// Neutre — compte générique (fond primary).
  neutral,

  /// Information (bleu).
  info,

  /// Succès (vert).
  success,

  /// Avertissement (orange).
  warning,

  /// Erreur/danger (rouge).
  error,
}

/// Badge Nubia : pastille compteur ou notification.
///
/// Affiche une petite pill avec un [count] entier ou un [label] texte.
/// Les couleurs proviennent de [NubiaTokens] pour les variants sémantiques.
///
/// - [count] : entier à afficher (mutuellement exclusif avec [label]).
/// - [label] : texte court à afficher (mutuellement exclusif avec [count]).
/// - [variant] : couleur sémantique (défaut [NubiaBadgeVariant.neutral]).
class NubiaBadge extends StatelessWidget {
  const NubiaBadge.count({
    super.key,
    required int count,
    this.variant = NubiaBadgeVariant.neutral,
  })  : _text = '$count',
        _isCount = true;

  const NubiaBadge.label({
    super.key,
    required String label,
    this.variant = NubiaBadgeVariant.neutral,
  })  : _text = label,
        _isCount = false;

  final String _text;
  final bool _isCount;
  final NubiaBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final Color bg;
    final Color fg;

    switch (variant) {
      case NubiaBadgeVariant.neutral:
        bg = cs.primary;
        fg = cs.onPrimary;
      case NubiaBadgeVariant.info:
        bg = tokens.infoBg;
        fg = tokens.infoFg;
      case NubiaBadgeVariant.success:
        bg = tokens.successBg;
        fg = tokens.successFg;
      case NubiaBadgeVariant.warning:
        bg = tokens.warningBg;
        fg = tokens.warningFg;
      case NubiaBadgeVariant.error:
        bg = tokens.dangerBg;
        fg = tokens.dangerFg;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: _isCount ? 6 : 8,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
