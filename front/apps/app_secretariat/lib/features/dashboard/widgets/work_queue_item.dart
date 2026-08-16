import 'package:flutter/material.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

/// Teinte de la pastille d'icône d'un [WorkQueueItem].
enum WorkQueueItemVariant {
  /// Accent primaire (émeraude) — défaut.
  primary,

  /// Accent info (bleu) — ex. demandes de créneau sans réponse (#5378).
  info,
}

/// Ligne « ticket » du panneau « À traiter maintenant » (maquette design-v2 :
/// icône teintée en pastille + titre/sous-titre + action secondaire). Chaque
/// ligne du panneau (#5376-#5379) instancie ce widget avec sa propre icône et
/// son action.
class WorkQueueItem extends StatelessWidget {
  const WorkQueueItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    this.showDivider = true,
    this.variant = WorkQueueItemVariant.primary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final bool showDivider;
  final WorkQueueItemVariant variant;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;

    final Color accentFg;
    final Color accentBg;
    switch (variant) {
      case WorkQueueItemVariant.primary:
        accentFg = cs.primary;
        accentBg = tokens.primarySubtleBg;
      case WorkQueueItemVariant.info:
        accentFg = tokens.infoFg;
        accentBg = tokens.infoBg;
    }

    return ListRow(
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: accentBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: accentFg),
      ),
      title: title,
      subtitle: subtitle,
      trailing: NubiaButton(
        label: actionLabel,
        icon: actionIcon,
        variant: NubiaButtonVariant.secondary,
        size: NubiaButtonSize.sm,
        onPressed: onAction,
      ),
      showDivider: showDivider,
    );
  }
}
