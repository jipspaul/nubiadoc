import 'package:flutter/material.dart';

/// Avatar cercle Nubia avec initiales texte.
///
/// Affiche les initiales du patient dans un cercle coloré avec la couleur
/// primaire du thème courant. Utilisé dans l'AppBar du [DashboardScreen].
class NubiaAvatar extends StatelessWidget {
  const NubiaAvatar({super.key, required this.initials, this.radius = 18.0});

  /// Initiales à afficher (ex. « MD »).
  final String initials;

  /// Rayon du cercle (défaut 18).
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
