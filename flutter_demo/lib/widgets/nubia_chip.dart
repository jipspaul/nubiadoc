import 'package:flutter/material.dart';

import '../theme/nubia_colors.dart';
import '../theme/nubia_tokens.dart';

/// Variantes de [NubiaChip] (cf. `design/07-handoff/01-composants.md` §5).
enum NubiaChipVariant {
  /// Bascule on/off. L'état [NubiaChip.selected] est piloté par le parent
  /// (le tap déclenche [NubiaChip.onTap]).
  filter,

  /// Sélection unique de type radio dans un groupe — gérée par le parent.
  choice,

  /// Jeton supprimable : affiche un « × » qui appelle [NubiaChip.onRemove].
  input,
}

/// Chip Nubia : filtre, choix ou input supprimable.
///
/// Hauteur 32, padding horizontal 12, rayon `full`. États : default
/// (bordure `border/default`) ; selected (fond `brand50`, bordure `brand200`,
/// texte `brand800`) ; disabled (aucun callback fourni).
class NubiaChip extends StatelessWidget {
  const NubiaChip({
    super.key,
    required this.label,
    this.variant = NubiaChipVariant.filter,
    this.selected = false,
    this.icon,
    this.onTap,
    this.onRemove,
  });

  /// Texte affiché dans le chip.
  final String label;

  /// Comportement du chip (filtre / choix / input).
  final NubiaChipVariant variant;

  /// État sélectionné (piloté par le parent).
  final bool selected;

  /// Icône leading optionnelle.
  final IconData? icon;

  /// Appelé au tap sur le corps du chip (`filter` / `choice`).
  final VoidCallback? onTap;

  /// Uniquement pour [NubiaChipVariant.input] : appelé au tap sur le « × ».
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final bool enabled = onTap != null || onRemove != null;

    final Color background =
        selected ? NubiaColors.brand50 : Colors.transparent;
    Color borderColor = selected ? NubiaColors.brand200 : tokens.borderDefault;
    Color foreground = selected ? NubiaColors.brand800 : scheme.onSurface;
    if (!enabled) {
      foreground = tokens.textTertiary;
      if (!selected) borderColor = tokens.borderSubtle;
    }

    final IconData? leadingIcon = icon;

    final Widget body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingIcon != null) ...[
            Icon(leadingIcon, size: 16, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
          if (variant == NubiaChipVariant.input) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Icon(Icons.close, size: 16, color: foreground),
            ),
          ],
        ],
      ),
    );

    final Widget chip = Material(
      color: background,
      shape: StadiumBorder(side: BorderSide(color: borderColor)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(height: 32, child: body),
      ),
    );

    if (variant == NubiaChipVariant.filter) {
      return Semantics(toggled: selected, child: chip);
    }
    return chip;
  }
}
