import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../invoice_reminder_cubit.dart';

/// Bouton « Relancer le patient » + historique des relances (#7205),
/// affiché sur le détail d'une facture (devis signé) échue — secrétariat et
/// praticien partagent cette même page (`DevisDetailPage`).
///
/// Doit être placée dans un `BlocProvider<InvoiceReminderCubit>`.
class InvoiceReminderSection extends StatefulWidget {
  const InvoiceReminderSection({super.key, required this.quote});

  final CabinetQuote quote;

  @override
  State<InvoiceReminderSection> createState() =>
      _InvoiceReminderSectionState();
}

class _InvoiceReminderSectionState extends State<InvoiceReminderSection> {
  @override
  void initState() {
    super.initState();
    context.read<InvoiceReminderCubit>().load(widget.quote.id);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<InvoiceReminderCubit, InvoiceReminderState>(
      listenWhen: (previous, current) =>
          current is InvoiceReminderLoaded && current.sendError != null,
      listener: (context, state) {
        final sendError = (state as InvoiceReminderLoaded).sendError!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              key: const Key('invoice_reminder_send_error_snackbar'),
              content: Text(sendError),
            ),
          );
      },
      builder: (context, state) {
        final sending = state is InvoiceReminderLoaded && state.sending;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NubiaButton(
              key: const Key('btn_relancer_patient'),
              label: 'Relancer le patient',
              icon: Icons.notifications_active_outlined,
              size: NubiaButtonSize.lg,
              isLoading: sending,
              onPressed: sending
                  ? null
                  : () => context
                      .read<InvoiceReminderCubit>()
                      .send(widget.quote.id),
            ),
            const SizedBox(height: 16),
            _ReminderHistoryCard(state: state),
          ],
        );
      },
    );
  }
}

class _ReminderHistoryCard extends StatelessWidget {
  const _ReminderHistoryCard({required this.state});

  final InvoiceReminderState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NubiaCard(
      key: const Key('invoice_reminder_history'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Relances envoyées', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          switch (state) {
            InvoiceReminderLoading() => const Center(
                key: Key('invoice_reminder_history_loading'),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            InvoiceReminderError(:final message) => Text(
                key: const Key('invoice_reminder_history_error'),
                message,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            InvoiceReminderLoaded(history: []) => Text(
                key: const Key('invoice_reminder_history_empty'),
                'Aucune relance envoyée pour le moment.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            InvoiceReminderLoaded(:final history) => Column(
                key: const Key('invoice_reminder_history_list'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, reminder) in history.indexed) ...[
                    if (index > 0) const Divider(height: 16),
                    _ReminderRow(reminder: reminder),
                  ],
                ],
              ),
          },
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder});

  final InvoiceReminder reminder;

  String _channelLabel(InvoiceReminderChannel channel) => switch (channel) {
        InvoiceReminderChannel.push => 'Notification',
        InvoiceReminderChannel.email => 'E-mail',
        InvoiceReminderChannel.unknown => 'Relance',
      };

  IconData _channelIcon(InvoiceReminderChannel channel) => switch (channel) {
        InvoiceReminderChannel.push => Icons.notifications_outlined,
        InvoiceReminderChannel.email => Icons.email_outlined,
        InvoiceReminderChannel.unknown => Icons.send_outlined,
      };

  String _formatDateTime(DateTime d) {
    final local = d.toLocal();
    final date = '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time = '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date à $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          _channelIcon(reminder.channel),
          size: 18,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _channelLabel(reminder.channel),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          _formatDateTime(reminder.sentAt),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
