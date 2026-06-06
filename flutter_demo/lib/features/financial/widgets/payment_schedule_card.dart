import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/financial_bloc.dart';
import '../bloc/financial_event.dart';
import '../bloc/financial_state.dart';
import '../models/financial_summary.dart';

/// Carte de l'échéancier multi-jalons avec bouton de paiement in-app.
class PaymentScheduleCard extends StatelessWidget {
  const PaymentScheduleCard({
    super.key,
    required this.milestones,
    required this.patientId,
  });

  final List<PaymentMilestone> milestones;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Échéancier', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            ...milestones.map(
              (m) => _MilestoneRow(milestone: m, patientId: patientId),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneRow extends StatelessWidget {
  const _MilestoneRow({
    required this.milestone,
    required this.patientId,
  });

  final PaymentMilestone milestone;
  final String patientId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isPaid = milestone.status == MilestoneStatus.paid;
    final isOverdue = milestone.status == MilestoneStatus.overdue;

    final Color statusColor = isPaid
        ? scheme.primary
        : isOverdue
            ? scheme.error
            : scheme.onSurfaceVariant;

    final IconData statusIcon = isPaid
        ? Icons.check_circle_outline
        : isOverdue
            ? Icons.warning_amber_outlined
            : Icons.radio_button_unchecked;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(statusIcon, size: 20, color: statusColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(milestone.label, style: textTheme.bodyMedium),
                Text(
                  _formatDate(milestone.dueDate),
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(milestone.amountCents / 100).toStringAsFixed(2)} €',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (!isPaid) ...[
            const SizedBox(width: 8),
            BlocBuilder<FinancialBloc, FinancialState>(
              builder: (context, state) {
                final loading = state is FinancialPaymentInProgress;
                return FilledButton(
                  onPressed: loading
                      ? null
                      : () => context.read<FinancialBloc>().add(
                            FinancialPaymentRequested(
                              patientId: patientId,
                              milestoneId: milestone.id,
                              amountCents: milestone.amountCents,
                            ),
                          ),
                  child: const Text('Payer'),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}
