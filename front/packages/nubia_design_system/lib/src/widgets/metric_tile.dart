// lib/presentation/widgets/metric_tile.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_colors.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Teinte d'accent d'un [MetricTile].
enum MetricTileVariant {
  /// Accent primaire (émeraude).
  neutral,

  /// Accent avertissement (orange).
  warning,

  /// Accent danger (rouge).
  danger,
}

/// Tuile de métrique (dashboard) : icône + valeur (`h3`) + libellé (`caption`).
///
/// Carte surface, rayon 12, ombre douce `sm`, bordure subtile. L'icône est
/// posée dans une pastille teintée selon [variant] ; la valeur utilise les
/// chiffres tabulaires. La variante alerte (`warning` / `danger`) reteinte la
/// pastille pour signaler un seuil.
///
/// - [icon] : icône Material affichée dans la pastille.
/// - [value] : valeur mise en avant (ex. « 3 », « 1 240 € »).
/// - [label] : libellé descriptif (ex. « À signer »).
/// - [variant] : teinte d'accent (défaut [MetricTileVariant.neutral]).
/// - [onTap] : rend la tuile interactive si fourni.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.variant = MetricTileVariant.neutral,
    this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final MetricTileVariant variant;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final Color accentFg;
    final Color accentBg;
    switch (variant) {
      case MetricTileVariant.neutral:
        accentFg = cs.primary;
        accentBg = tokens.primarySubtleBg;
      case MetricTileVariant.warning:
        accentFg = tokens.warningFg;
        accentBg = tokens.warningBg;
      case MetricTileVariant.danger:
        accentFg = tokens.dangerFg;
        accentBg = tokens.dangerBg;
    }

    final Widget content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accentBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: accentFg),
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: textTheme.headlineSmall?.copyWith(
                color: cs.onSurface,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: tokens.borderSubtle),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        // Ombre douce `sm` : 0 1px 2px rgba(28,25,23,.05).
        boxShadow: [
          BoxShadow(
            color: NubiaColors.n900.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: cs.surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}
