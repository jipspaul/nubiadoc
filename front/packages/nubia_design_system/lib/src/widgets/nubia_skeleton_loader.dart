// lib/presentation/widgets/nubia_skeleton_loader.dart
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Placeholder de chargement avec animation shimmer.
///
/// Affiche un bloc gris arrondi animé le temps que les données se chargent.
/// - [width] : largeur du bloc (défaut : `double.infinity`).
/// - [height] : hauteur du bloc.
/// - [borderRadius] : rayon des coins (défaut : 8 px).
class NubiaSkeletonLoader extends StatelessWidget {
  const NubiaSkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: cs.surfaceContainerHighest,
      highlightColor: cs.surfaceContainerLow,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
