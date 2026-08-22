// lib/presentation/widgets/segmented_control.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_colors.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Contrôle segmenté (2-3 segments) — ex. « À venir » / « Historique ».
///
/// Piste `bg/page` + bordure subtile, rayon `md`. Le segment actif est rempli
/// `brand/50` ([NubiaTokens.primarySubtleBg]) avec texte `brand`/600 ; les
/// segments inactifs sont transparents, texte tertiaire/500. Navigation
/// clavier via [InkWell] focalisable + [Semantics].
///
/// - [segments] : libellés (2 ou 3 éléments).
/// - [selectedIndex] : index du segment actif.
/// - [onChanged] : callback à la sélection d'un segment.
/// - [counts] : pastille de comptage optionnelle par segment (même longueur
///   que [segments] si fournie ; `null` par élément masque la pastille de ce
///   segment).
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    this.counts,
  })  : assert(
          segments.length >= 2 && segments.length <= 3,
          'SegmentedControl attend 2 ou 3 segments',
        ),
        assert(
          selectedIndex >= 0 && selectedIndex < segments.length,
          'selectedIndex hors bornes',
        ),
        assert(
          counts == null || counts.length == segments.length,
          'counts doit avoir la même longueur que segments',
        );

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<int?>? counts;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          for (int i = 0; i < segments.length; i++)
            Expanded(
              child: _Segment(
                label: segments[i],
                count: counts?[i],
                selected: i == selectedIndex,
                onTap: () => onChanged(i),
                activeBg: tokens.primarySubtleBg,
                activeFg: tokens.primarySubtleFg,
                inactiveFg: tokens.textTertiary,
                textStyle: textTheme.labelLarge,
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    this.count,
    required this.selected,
    required this.onTap,
    required this.activeBg,
    required this.activeFg,
    required this.inactiveFg,
    required this.textStyle,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;
  final Color activeBg;
  final Color activeFg;
  final Color inactiveFg;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label ($count)',
      child: Material(
        color: selected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyle?.copyWith(
                      color: selected ? activeFg : inactiveFg,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  _CountPastille(count: count!, selected: selected),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pastille de comptage (`.sg .c`) — 11px/600, rayon 99, min-width 18,
/// padding 1px 6px. Fond `n200`/texte `n600` inactive, fond `brand700`/texte
/// blanc active (`.sg.on .c`).
class _CountPastille extends StatelessWidget {
  const _CountPastille({required this.count, required this.selected});

  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? NubiaColors.brand700 : NubiaColors.n200,
        borderRadius: BorderRadius.circular(99),
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: selected ? Colors.white : NubiaColors.n600,
        ),
      ),
    );
  }
}
