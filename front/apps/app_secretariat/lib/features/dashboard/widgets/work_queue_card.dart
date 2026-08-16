import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import '../expiring_quotes_summary_cubit.dart';
import '../patient_messages_summary_cubit.dart';
import 'work_queue_item.dart';

/// Panneau « À traiter maintenant » (maquette design-v2, colonne droite du
/// tableau de bord) : file de tickets d'action rapide. Lignes couvertes :
/// demandes de créneau sans réponse (#5378), devis qui expirent cette
/// semaine (#5377) et messages patients non lus (#5379) — RDV non confirmé
/// reste hors périmètre de ces tickets.
class WorkQueueCard extends StatelessWidget {
  const WorkQueueCard({
    super.key,
    required this.waitingCount,
    this.oldestWaitingRequestAgeDays,
  });

  /// Nombre de demandes de créneau sans réponse (#5378).
  final int waitingCount;

  /// Ancienneté (en jours) de la plus ancienne demande de créneau sans
  /// réponse — `null` si la liste d'attente est vide.
  final int? oldestWaitingRequestAgeDays;

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
          WorkQueueItem(
            key: const Key('work_queue_waiting_list_row'),
            icon: Icons.hourglass_top,
            title: '$waitingCount demandes de créneau sans réponse',
            subtitle: oldestWaitingRequestAgeDays == null
                ? null
                : 'La plus ancienne attend depuis '
                    '$oldestWaitingRequestAgeDays jours',
            actionLabel: 'Ouvrir',
            actionIcon: Icons.arrow_forward,
            onAction: () => context.push('/liste-attente'),
            variant: WorkQueueItemVariant.info,
          ),
          BlocBuilder<ExpiringQuotesSummaryCubit, ExpiringQuotesSummaryState>(
            builder: (context, state) => switch (state) {
              ExpiringQuotesSummaryLoading() => const Padding(
                  key: Key('work_queue_card_quotes_loading'),
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: NubiaSkeletonLoader(height: 56, borderRadius: 8),
                ),
              ExpiringQuotesSummaryError(:final message) => Padding(
                  key: const Key('work_queue_card_quotes_error'),
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    message,
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ExpiringQuotesSummaryLoaded(:final quotes) => quotes.isEmpty
                  ? const SizedBox.shrink(
                      key: Key('work_queue_expiring_quotes_row_empty'),
                    )
                  : WorkQueueItem(
                      key: const Key('work_queue_expiring_quotes_row'),
                      icon: Icons.description,
                      title: '${quotes.length} devis expirent cette semaine',
                      subtitle: quotes
                          .map(
                            (q) =>
                                '${q.patientName} (${_formatDayMonth(q.expiresAt!)})',
                          )
                          .join(', '),
                      actionLabel: 'Relancer',
                      actionIcon: Icons.send,
                      onAction: () => context.push('/devis'),
                      variant: WorkQueueItemVariant.warning,
                    ),
            },
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
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
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

/// Formate une date en `JJ/MM` (ex. « 16/08 »), verbatim maquette.
String _formatDayMonth(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/'
    '${date.month.toString().padLeft(2, '0')}';
