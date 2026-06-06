import 'package:flutter/material.dart';

import '../../models/financial_summary.dart';

/// Carte de résumé financier : montant dû, payé, restant + barre de progression.
class FinancialSummaryCard extends StatelessWidget {
  const FinancialSummaryCard({super.key, required this.summary});

  final FinancialSummary summary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final paidEuros = summary.totalPaidCents / 100;
    final totalEuros = summary.totalDueCents / 100;
    final remainingEuros = summary.remainingCents / 100;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Résumé financier', style: textTheme.titleLarge),
            const SizedBox(height: 12),
            _AmountRow(
              label: 'Total dû',
              euros: totalEuros,
              color: scheme.onSurface,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Payé',
              euros: paidEuros,
              color: scheme.primary,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Restant',
              euros: remainingEuros,
              color: scheme.error,
            ),
            const SizedBox(height: 16),
            _PaymentProgressBar(fraction: summary.paidFraction),
            const SizedBox(height: 4),
            Text(
              '${(summary.paidFraction * 100).toStringAsFixed(0)} % réglé',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.label,
    required this.euros,
    required this.color,
  });

  final String label;
  final double euros;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: textTheme.bodyMedium),
        Text(
          '${euros.toStringAsFixed(2)} €',
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _PaymentProgressBar extends StatelessWidget {
  const _PaymentProgressBar({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 8,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        valueColor: AlwaysStoppedAnimation<Color>(
          Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}
