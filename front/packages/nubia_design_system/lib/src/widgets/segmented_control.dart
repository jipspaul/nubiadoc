// lib/presentation/widgets/segmented_control.dart
import 'package:flutter/material.dart';
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
class SegmentedControl extends StatelessWidget {
  const SegmentedControl({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
  })  : assert(
          segments.length >= 2 && segments.length <= 3,
          'SegmentedControl attend 2 ou 3 segments',
        ),
        assert(
          selectedIndex >= 0 && selectedIndex < segments.length,
          'selectedIndex hors bornes',
        );

  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

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
    required this.selected,
    required this.onTap,
    required this.activeBg,
    required this.activeFg,
    required this.inactiveFg,
    required this.textStyle,
  });

  final String label;
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
      label: label,
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
        ),
      ),
    );
  }
}
