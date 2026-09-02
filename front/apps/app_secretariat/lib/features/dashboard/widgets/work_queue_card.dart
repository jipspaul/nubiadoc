import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../expiring_quotes_summary_cubit.dart';
import '../patient_messages_summary_cubit.dart';
import 'work_queue_item.dart';

/// Panneau « À traiter maintenant » (maquette design-v2, colonne droite du
/// tableau de bord) : file de tickets d'action rapide, avec compteur de
/// sujets et état vide rassurant quand il n'y a rien à traiter (#5375).
/// Lignes couvertes : RDV du jour non confirmés (#5376), demandes de
/// créneau sans réponse (#5378), devis qui expirent cette semaine (#5377)
/// et messages patients non lus (#5379).
class WorkQueueCard extends StatelessWidget {
  const WorkQueueCard({
    super.key,
    required this.waitingCount,
    this.oldestWaitingRequestAgeDays,
    this.pendingAppointmentsToday = const [],
  });

  /// Nombre de demandes de créneau sans réponse (#5378).
  final int waitingCount;

  /// Ancienneté (en jours) de la plus ancienne demande de créneau sans
  /// réponse — `null` si la liste d'attente est vide.
  final int? oldestWaitingRequestAgeDays;

  /// RDV du jour au statut `requested` (non confirmés) — ligne « RDV non
  /// confirmé » (#5376).
  final List<AgendaEntry> pendingAppointmentsToday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final quotesState = context.watch<ExpiringQuotesSummaryCubit>().state;
    final messagesState = context.watch<PatientMessagesSummaryCubit>().state;

    // Un sujet ne compte (et ne s'affiche) que lorsqu'il est confirmé —
    // pendant le chargement/l'erreur d'une section, elle affiche son propre
    // squelette/message plutôt qu'une ligne, et ne doit ni gonfler le badge
    // ni déclencher l'état vide (#5375 : « N sujets » = lignes réellement
    // présentes, pas des compteurs à zéro non actionnables).
    final bool showWaitingRow = waitingCount > 0;
    final bool showQuotesRow = quotesState is ExpiringQuotesSummaryLoaded &&
        quotesState.quotes.isNotEmpty;
    final bool showMessagesRow =
        messagesState is PatientMessagesSummaryLoaded &&
            messagesState.unreadCount > 0;

    final bool quotesSectionEmpty =
        quotesState is ExpiringQuotesSummaryLoaded && !showQuotesRow;
    final bool messagesSectionEmpty =
        messagesState is PatientMessagesSummaryLoaded && !showMessagesRow;
    final bool showEmptyState = pendingAppointmentsToday.isEmpty &&
        !showWaitingRow &&
        quotesSectionEmpty &&
        messagesSectionEmpty;

    final int subjectCount = pendingAppointmentsToday.length +
        (showWaitingRow ? 1 : 0) +
        (showQuotesRow ? 1 : 0) +
        (showMessagesRow ? 1 : 0);

    final List<CabinetQuote> expiringQuotes =
        quotesState is ExpiringQuotesSummaryLoaded
            ? quotesState.quotes
            : const [];
    final int unreadMessagesCount =
        messagesState is PatientMessagesSummaryLoaded
            ? messagesState.unreadCount
            : 0;
    final int urgentUnreadCount = messagesState is PatientMessagesSummaryLoaded
        ? messagesState.urgentUnreadCount
        : 0;
    final String? urgentPatientName =
        messagesState is PatientMessagesSummaryLoaded
            ? messagesState.urgentPatientName
            : null;
    final String? urgentConversationId =
        messagesState is PatientMessagesSummaryLoaded
            ? messagesState.urgentConversationId
            : null;

    // Une section encore en chargement/erreur affiche son propre widget
    // sous les lignes — la dernière ligne garde alors son séparateur.
    final bool somethingFollowsRows = quotesState is! ExpiringQuotesSummaryLoaded ||
        messagesState is! PatientMessagesSummaryLoaded;

    final List<Widget Function(bool showDivider)> rowBuilders = [
      for (final entry in pendingAppointmentsToday)
        (showDivider) => WorkQueueItem(
              key: Key('work_queue_pending_appointment_row_${entry.id}'),
              icon: Icons.event_busy,
              title: "${entry.patientName ?? 'Patient'} n'a pas confirmé "
                  'son RDV de ${_formatTime(entry.startsAt)}',
              actionLabel: 'Appeler',
              actionIcon: Icons.call,
              actionVariant: NubiaButtonVariant.primary,
              variant: WorkQueueItemVariant.danger,
              // #6246 : cible le RDV du ticket (volet latéral déjà ouvert
              // dessus) plutôt que la grille hebdomadaire complète.
              onAction: () => context.push('/agenda', extra: entry.id),
              showDivider: showDivider,
            ),
      if (showWaitingRow)
        (showDivider) => WorkQueueItem(
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
              showDivider: showDivider,
            ),
      if (showQuotesRow)
        (showDivider) => WorkQueueItem(
              key: const Key('work_queue_expiring_quotes_row'),
              icon: Icons.description,
              title: '${expiringQuotes.length} devis expirent cette semaine',
              subtitle: expiringQuotes
                  .map(
                    (q) => '${q.patientName} '
                        '(${_formatDayMonth(q.expiresAt!)})',
                  )
                  .join(', '),
              actionLabel: 'Relancer',
              actionIcon: Icons.send,
              // #6246 : ouvre le volet du devis le plus urgent (liste triée
              // par expiration croissante) plutôt que les 200 devis du cabinet.
              onAction: () =>
                  context.push('/devis', extra: expiringQuotes.first.id),
              variant: WorkQueueItemVariant.warning,
              showDivider: showDivider,
            ),
      if (showMessagesRow)
        (showDivider) => WorkQueueItem(
              key: const Key('work_queue_unread_messages_row'),
              icon: Icons.chat_bubble,
              title: '$unreadMessagesCount messages patients non lus',
              subtitle: urgentUnreadCount > 0
                  ? 'Dont $urgentUnreadCount marqué urgent '
                      'par $urgentPatientName'
                  : null,
              actionLabel: 'Ouvrir',
              actionIcon: Icons.arrow_forward,
              // #6246 : ouvre directement la conversation urgente nommée par
              // le sous-titre quand elle est connue, plutôt que la liste
              // complète sur l'onglet « Tous ».
              onAction: () =>
                  context.push('/messages', extra: urgentConversationId),
              showDivider: showDivider,
            ),
    ];

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
                Expanded(
                  child: Text(
                    'À traiter maintenant',
                    style:
                        textTheme.titleMedium?.copyWith(color: cs.onSurface),
                  ),
                ),
                const SizedBox(width: 8),
                NubiaBadge.label(
                  key: const Key('work_queue_card_badge'),
                  label: '$subjectCount sujets',
                ),
              ],
            ),
          ),
          for (var i = 0; i < rowBuilders.length; i++)
            rowBuilders[i](
              i < rowBuilders.length - 1 || somethingFollowsRows,
            ),
          if (quotesState is ExpiringQuotesSummaryLoading)
            const Padding(
              key: Key('work_queue_card_quotes_loading'),
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: NubiaSkeletonLoader(height: 56, borderRadius: 8),
            ),
          if (quotesState is ExpiringQuotesSummaryError)
            Padding(
              key: const Key('work_queue_card_quotes_error'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                quotesState.message,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (messagesState is PatientMessagesSummaryLoading)
            const Padding(
              key: Key('work_queue_card_loading'),
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: NubiaSkeletonLoader(height: 56, borderRadius: 8),
            ),
          if (messagesState is PatientMessagesSummaryError)
            Padding(
              key: const Key('work_queue_card_error'),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                messagesState.message,
                style: textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          if (showEmptyState)
            const Padding(
              key: Key('work_queue_card_empty'),
              padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: NubiaEmptyState(
                icon: Icons.task_alt_outlined,
                title: 'Rien à traiter pour le moment',
                subtitle: 'Les nouvelles demandes apparaîtront ici dès '
                    "qu'elles nécessiteront une action.",
              ),
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

/// Formate une heure en `HH:MM` (ex. « 15:30 »), verbatim maquette.
String _formatTime(DateTime date) =>
    '${date.hour.toString().padLeft(2, '0')}:'
    '${date.minute.toString().padLeft(2, '0')}';
