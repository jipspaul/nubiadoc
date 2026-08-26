import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../../router/app_router.dart';

/// Carte « À traiter » (#5049, maquette design-v2 praticien) : remplace les
/// `MetricTile` isolés « Confirmations en attente » / « Messages non lus »
/// par une file unique de lignes actionnables, chacune conservant sa route
/// de destination (#3374).
///
/// « Notes de séance à finaliser » et « travaux labo reçus » rejoindront
/// cette file quand leurs compteurs existeront côté domaine ; en attendant
/// elles restent masquées (pas de donnée à afficher).
class PendingActionsCard extends StatelessWidget {
  const PendingActionsCard({super.key, required this.summary});

  final ProDashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;

    // #3374 : chaque ligne est un raccourci vers l'écran correspondant.
    // « Confirmations en attente » n'a pas d'écran dédié → l'agenda (où se
    // font les confirmations). « Notes de séance à finaliser » et « travaux
    // labo reçus » rejoindront la file quand leurs compteurs existeront côté
    // domaine (#5049) — masquées tant que la donnée est absente.
    final rows = <Widget>[
      ListRow(
        key: const Key('metric_confirmations'),
        leading: _ActionIcon(
          icon: Icons.pending_actions_outlined,
          foreground: tokens.warningFg,
          background: tokens.warningBg,
        ),
        title: 'Confirmations en attente',
        trailing: StatusPill(
          label: '${summary.pendingConfirmations}',
          variant: summary.pendingConfirmations > 0
              ? StatusPillVariant.warning
              : StatusPillVariant.neutral,
        ),
        onTap: () => context.go(AppRouter.agenda),
      ),
      ListRow(
        key: const Key('metric_messages'),
        leading: _ActionIcon(
          icon: Icons.chat_bubble_outline,
          foreground: cs.primary,
          background: tokens.primarySubtleBg,
        ),
        title: 'Messages non lus',
        trailing: StatusPill(
          label: '${summary.unreadMessages}',
          variant: summary.unreadMessages > 0
              ? StatusPillVariant.warning
              : StatusPillVariant.neutral,
        ),
        onTap: () => context.go(AppRouter.messages),
        showDivider: false,
      ),
    ];

    return NubiaCard(
      key: const Key('pending_actions_card'),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.pending_actions_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  'À traiter',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
                const Spacer(),
                StatusPill(
                  label: '${rows.length}',
                  variant: StatusPillVariant.neutral,
                ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: foreground),
    );
  }
}
