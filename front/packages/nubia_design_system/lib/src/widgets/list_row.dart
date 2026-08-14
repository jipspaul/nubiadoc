// lib/presentation/widgets/list_row.dart
import 'package:flutter/material.dart';
import 'package:nubia_design_system/src/theme/nubia_tokens.dart';

/// Ligne de liste générique : leading + titre/sous-titre + trailing.
///
/// Remplace `ListTile` brut. Hauteur mini 56, séparateur bas optionnel, et une
/// variante non-lu (point coloré `primary` + titre en poids renforcé). Le
/// [leading] accueille typiquement un `NubiaAvatar` ou une icône, le [trailing]
/// un badge / une valeur / un chevron.
///
/// - [title] : texte principal.
/// - [subtitle] : texte secondaire optionnel (tronqué sur une ligne).
/// - [subtitleWidget] : remplace [subtitle] par un widget libre (ex. texte
///   multi-ligne avec tonalité de couleur) quand un simple `String` ne
///   suffit pas. Ignoré si [subtitle] est fourni.
/// - [leading] : widget de gauche optionnel (avatar / icône).
/// - [trailing] : widget de droite optionnel (badge / valeur / chevron).
/// - [unread] : variante non-lu (point `primary` + titre renforcé).
/// - [showDivider] : affiche le séparateur bas (défaut `true`).
/// - [onTap] : callback au tap sur la ligne.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.leading,
    this.trailing,
    this.unread = false,
    this.showDivider = true,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleWidget;
  final Widget? leading;
  final Widget? trailing;
  final bool unread;
  final bool showDivider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    final Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight:
                                unread ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color:
                            unread ? cs.onSurfaceVariant : tokens.textTertiary,
                        fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ] else if (subtitleWidget != null) ...[
                    const SizedBox(height: 2),
                    subtitleWidget!,
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    );

    final Widget tappable = onTap == null
        ? row
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: row),
          );

    if (!showDivider) {
      return tappable;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tappable,
        Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
      ],
    );
  }
}
