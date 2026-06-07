// lib/presentation/widgets/nubia_avatar.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Avatar Nubia : image réseau ou initiales texte.
///
/// - [imageUrl] : URL de l'image (ex. photo de profil). Si null ou en erreur,
///   affiche les initiales.
/// - [initials] : texte à afficher quand il n'y a pas d'image (ex. « MD »).
/// - [radius] : rayon du cercle (défaut 20 dp).
class NubiaAvatar extends StatelessWidget {
  const NubiaAvatar({
    super.key,
    this.imageUrl,
    required this.initials,
    this.radius = 20.0,
  });

  final String? imageUrl;
  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: cs.primaryContainer,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => _Initials(
              initials: initials,
              radius: radius,
            ),
          ),
        ),
      );
    }

    return _Initials(initials: initials, radius: radius);
  }
}

// ---------------------------------------------------------------------------

class _Initials extends StatelessWidget {
  const _Initials({required this.initials, required this.radius});

  final String initials;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: cs.primaryContainer,
      child: Text(
        initials,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
              fontSize: radius * 0.75,
            ),
      ),
    );
  }
}
