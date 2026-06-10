import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/widgets/status_pill.dart';

/// En-tête du détail du devis : praticien, montant total, reste à charge,
/// statut et date d'expiration.
class QuoteDetailHeader extends StatelessWidget {
  const QuoteDetailHeader({super.key, required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                quote.practitionerName,
                style: theme.textTheme.titleLarge,
              ),
            ),
            StatusPill(
              label: _statusLabel(quote.status),
              variant: _statusVariant(quote.status),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (quote.expiresAt != null) ...[
          Text(
            'Valable jusqu\'au ${_formatDate(quote.expiresAt!)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: quote.isExpired
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            Expanded(
              child: _AmountChip(
                label: 'Total traitement',
                cents: quote.totalCents,
                bold: false,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _AmountChip(
                label: 'Reste à charge',
                cents: quote.patientShareCents,
                bold: true,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static String _statusLabel(QuoteStatus status) {
    return switch (status) {
      QuoteStatus.draft => 'Brouillon',
      QuoteStatus.sent => 'À signer',
      QuoteStatus.signed => 'Signé',
      QuoteStatus.expired => 'Expiré',
      QuoteStatus.cancelled => 'Annulé',
    };
  }

  static StatusPillVariant _statusVariant(QuoteStatus status) {
    return switch (status) {
      QuoteStatus.sent => StatusPillVariant.warning,
      QuoteStatus.signed => StatusPillVariant.success,
      QuoteStatus.expired || QuoteStatus.cancelled => StatusPillVariant.error,
      QuoteStatus.draft => StatusPillVariant.info,
    };
  }

  static String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }
}

class _AmountChip extends StatelessWidget {
  const _AmountChip({
    required this.label,
    required this.cents,
    required this.bold,
  });

  final String label;
  final int cents;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${(cents / 100).toStringAsFixed(2)} €',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
