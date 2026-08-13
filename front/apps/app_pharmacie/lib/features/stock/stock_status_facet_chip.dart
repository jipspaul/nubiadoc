import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Chip de facette de statut : pastille de couleur + libellé + compteur.
class StockStatusFacetChip extends StatelessWidget {
  const StockStatusFacetChip({
    super.key,
    required this.label,
    required this.count,
    required this.dotColor,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color dotColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final Color background =
        selected ? NubiaColors.brand50 : Colors.transparent;
    final Color borderColor =
        selected ? NubiaColors.brand200 : tokens.borderDefault;
    final Color foreground =
        selected ? NubiaColors.brand800 : Theme.of(context).colorScheme.onSurface;

    return Semantics(
      toggled: selected,
      child: Material(
        color: background,
        shape: StadiumBorder(side: BorderSide(color: borderColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$label ($count)',
                    style: textTheme.labelMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
