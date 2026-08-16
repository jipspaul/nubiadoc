// lib/presentation/widgets/provider_card.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_colors.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';
import 'package:nubia_design_system/src/widgets/nubia_avatar.dart';
import 'package:nubia_design_system/src/widgets/nubia_badge.dart';

/// Carte praticien (résultat de recherche / annuaire).
///
/// Compose [NubiaAvatar] + nom (`title`/500) + spécialité (`caption`) +
/// marqueur RPPS vérifié (check) + distance (`caption`) + badge disponibilité
/// ([NubiaBadge] `success`) + chevron. Carte interactive (tap), hauteur mini
/// 84, rayon 12, ombre douce `sm`, bordure subtile — tokens uniquement.
///
/// - [name] : nom du praticien / cabinet.
/// - [specialty] : spécialité ou sous-titre (ex. « Chirurgien-dentiste »).
/// - [initials] : initiales de repli pour l'avatar (ex. « CL »).
/// - [imageUrl] : photo optionnelle du praticien.
/// - [availabilityLabel] : libellé de dispo (ex. « 1re dispo · Aujourd'hui »).
/// - [distance] : distance formatée (ex. « 1,2 km »).
/// - [rppsVerified] : affiche le marqueur RPPS vérifié à côté du nom.
/// - [onTap] : callback au tap sur la carte.
/// - [onViewProfile] : quand fourni et qu'il n'y a pas de créneau en ligne
///   ([availabilityLabel] null), remplace la ligne dispo/distance par le
///   bloc « Aucun créneau en ligne pour ce praticien » (maquette design-v2,
///   bloc `.nosl`) proposant l'accès à sa fiche/coordonnées — la carte n'est
///   jamais masquée ni laissée vide (#5358).
class ProviderCard extends StatelessWidget {
  const ProviderCard({
    super.key,
    required this.name,
    required this.specialty,
    required this.initials,
    this.imageUrl,
    this.availabilityLabel,
    this.distance,
    this.rppsVerified = false,
    this.onTap,
    this.onViewProfile,
  });

  final String name;
  final String specialty;
  final String initials;
  final String? imageUrl;
  final String? availabilityLabel;
  final String? distance;
  final bool rppsVerified;
  final VoidCallback? onTap;
  final VoidCallback? onViewProfile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    final bool noOnlineSlots = availabilityLabel == null && onViewProfile != null;

    final Widget content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 84),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            NubiaAvatar(imageUrl: imageUrl, initials: initials, radius: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (rppsVerified) ...[
                        const SizedBox(width: 4),
                        Icon(
                          Icons.verified_rounded,
                          size: 16,
                          color: cs.primary,
                          semanticLabel: 'RPPS vérifié',
                        ),
                      ],
                    ],
                  ),
                  // #3825 : pas de ligne (ni espace résiduel) quand la
                  // spécialité est vide.
                  if (specialty.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      specialty,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (noOnlineSlots) ...[
                    const SizedBox(height: 8),
                    _NoOnlineSlotsNotice(onViewProfile: onViewProfile!),
                  ] else if (availabilityLabel != null || distance != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (availabilityLabel != null)
                          NubiaBadge.label(
                            label: availabilityLabel!,
                            variant: NubiaBadgeVariant.success,
                          ),
                        if (availabilityLabel != null && distance != null)
                          const SizedBox(width: 8),
                        if (distance != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.place_outlined,
                                size: 13,
                                color: tokens.textTertiary,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                distance!,
                                style: textTheme.bodySmall?.copyWith(
                                  color: tokens.textTertiary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: tokens.textTertiary),
          ],
        ),
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
        child: InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// Bloc « aucun créneau en ligne » (maquette design-v2, bloc `.nosl`) : fond
/// `n50`, bordure pointillée, titre + action « Voir sa fiche et ses
/// coordonnées ». Remplace la ligne dispo/distance sans jamais masquer ni
/// laisser vide la carte praticien (#5358).
class _NoOnlineSlotsNotice extends StatelessWidget {
  const _NoOnlineSlotsNotice({required this.onViewProfile});

  final VoidCallback onViewProfile;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: double.infinity,
      child: CustomPaint(
        foregroundPainter: const _DashedRRectPainter(
          color: NubiaColors.n300,
          radius: 8,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: NubiaColors.n50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Aucun créneau en ligne pour ce praticien',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                InkWell(
                  key: const Key('no_online_slots_view_profile'),
                  onTap: onViewProfile,
                  child: Text(
                    'Voir sa fiche et ses coordonnées',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bordure pointillée d'un rectangle arrondi — Flutter n'a pas de
/// `BorderStyle.dashed` natif (maquette, bloc `.nosl`).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  static const _dashWidth = 4.0;
  static const _dashGap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
