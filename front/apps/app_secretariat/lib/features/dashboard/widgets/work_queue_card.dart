import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../patient_messages_summary_cubit.dart';
import 'work_queue_item.dart';

/// Panneau « À traiter maintenant » (maquette design-v2, colonne droite du
/// tableau de bord) : file de tickets d'action rapide. Pour l'instant une
/// seule ligne — messages patients non lus (#5379) — les autres lignes de la
/// maquette (RDV non confirmé, devis expirants, demandes de créneau) sont
/// hors périmètre de ce ticket.
class WorkQueueCard extends StatelessWidget {
  const WorkQueueCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return NubiaCard(
      key: const Key('work_queue_card'),
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
                  'À traiter maintenant',
                  style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
                ),
              ],
            ),
          ),
          BlocBuilder<PatientMessagesSummaryCubit, PatientMessagesSummaryState>(
            builder: (context, state) => switch (state) {
              PatientMessagesSummaryLoading() => const Padding(
                  key: Key('work_queue_card_loading'),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: NubiaSkeletonLoader(height: 56, borderRadius: 8),
                ),
              PatientMessagesSummaryError(:final message) => Padding(
                  key: const Key('work_queue_card_error'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    message,
                    style:
                        textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              PatientMessagesSummaryLoaded(
                :final unreadCount,
                :final urgentUnreadCount,
                :final urgentPatientName,
              ) =>
                WorkQueueItem(
                  key: const Key('work_queue_unread_messages_row'),
                  icon: Icons.chat_bubble,
                  title: '$unreadCount messages patients non lus',
                  subtitle: urgentUnreadCount > 0
                      ? 'Dont $urgentUnreadCount marqué urgent par $urgentPatientName'
                      : null,
                  actionLabel: 'Ouvrir',
                  actionIcon: Icons.arrow_forward,
                  onAction: () => context.push('/messages'),
                  showDivider: false,
                ),
            },
          ),
        ],
      ),
    );
  }
}
