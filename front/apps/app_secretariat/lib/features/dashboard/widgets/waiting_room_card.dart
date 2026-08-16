import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../waiting_room_summary_cubit.dart';

/// Seuil (nombre de personnes présentes) au-delà duquel le compteur bascule
/// en teinte warning (cf. maquette : 5 personnes présentes → compteur
/// warning), cohérent avec le badge du rail (#5388).
const _kPresentWarningThreshold = 5;

/// Carte « Salle d'attente » (#5381, colonne droite du tableau de bord) :
/// effectif présent + attente moyenne/la plus longue, avec lien « Ouvrir »
/// vers `/salle-attente`. Source : `WaitingRoomSummaryCubit`, qui réutilise
/// `ListWaitingRoomUseCase` (même donnée que le badge du rail et la page
/// salle d'attente elle-même — pas de nouvel appel réseau dédié).
class WaitingRoomCard extends StatelessWidget {
  const WaitingRoomCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('waiting_room_card'),
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
                  Icons.meeting_room_outlined,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Salle d\'attente',
                    style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                InkWell(
                  key: const Key('waiting_room_card_open_link'),
                  onTap: () => context.push('/salle-attente'),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Ouvrir',
                        style: textTheme.bodySmall?.copyWith(
                          color: NubiaColors.brand700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward,
                        size: 14,
                        color: NubiaColors.brand700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          BlocBuilder<WaitingRoomSummaryCubit, WaitingRoomSummaryState>(
            builder: (context, state) => switch (state) {
              WaitingRoomSummaryLoading() => const Padding(
                  key: Key('waiting_room_card_loading'),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: NubiaSkeletonLoader(height: 56, borderRadius: 8),
                ),
              WaitingRoomSummaryError(:final message) => Padding(
                  key: const Key('waiting_room_card_error'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    message,
                    style:
                        textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              WaitingRoomSummaryLoaded(
                :final presentCount,
                :final averageWaitMinutes,
                :final longestWaitMinutes,
              ) =>
                ListRow(
                  key: const Key('waiting_room_card_summary_row'),
                  leading: Icon(
                    Icons.groups,
                    size: 20,
                    color: NubiaColors.brand600,
                  ),
                  title: '$presentCount personne(s) présente(s)',
                  subtitle: presentCount == 0
                      ? 'Aucun patient en salle d\'attente.'
                      : 'Attente moyenne $averageWaitMinutes min · '
                          'une depuis $longestWaitMinutes min',
                  trailing: _PresentCountBadge(count: presentCount),
                  showDivider: false,
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _PresentCountBadge extends StatelessWidget {
  const _PresentCountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final isWarning = count >= _kPresentWarningThreshold;

    return Text(
      '$count',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: isWarning ? tokens.warningFg : cs.onSurface,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
    );
  }
}
