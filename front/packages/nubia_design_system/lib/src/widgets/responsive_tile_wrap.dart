import 'package:flutter/material.dart';

/// Bandeau de tuiles (KPI, métriques…) qui se répartissent en rangées de
/// largeur [tileWidth], et s'étirent à la largeur disponible quand une seule
/// tuile tient par rangée — plutôt que de laisser un vide à droite d'une
/// tuile figée à [tileWidth] (#8591).
class ResponsiveTileWrap extends StatelessWidget {
  const ResponsiveTileWrap({
    super.key,
    required this.tiles,
    this.tileWidth = 220,
    this.spacing = 16,
    this.runSpacing = 16,
  });

  final List<Widget> tiles;
  final double tileWidth;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final columns = ((maxWidth + spacing) / (tileWidth + spacing))
            .floor()
            .clamp(1, tiles.length);
        final effectiveWidth = columns > 1 ? tileWidth : maxWidth;
        return Wrap(
          spacing: spacing,
          runSpacing: runSpacing,
          children: [
            for (final tile in tiles)
              SizedBox(width: effectiveWidth, child: tile),
          ],
        );
      },
    );
  }
}
