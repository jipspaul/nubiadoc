import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/value_objects/amount_cents.dart';
import 'package:nubia_patient/presentation/widgets/status_pill.dart';

/// Tuile de liste affichant un résumé d'un [Quote].
///
/// Affiche : praticien, statut (badge), date de création, total et reste à charge.
class QuoteListTile extends StatelessWidget {
  const QuoteListTile({
    super.key,
    required this.quote,
    required this.onTap,
  });

  final Quote quote;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('quote_tile_${quote.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QuoteListTileHeader(quote: quote),
              const SizedBox(height: 10),
              _QuoteListTileAmounts(quote: quote, theme: theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteListTileHeader extends StatelessWidget {
  const _QuoteListTileHeader({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                quote.practitionerName,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 2),
              Text(
                _formatDate(quote.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        StatusPill(
          label: _statusLabel(quote.status),
          variant: _statusVariant(quote.status),
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

class _QuoteListTileAmounts extends StatelessWidget {
  const _QuoteListTileAmounts({
    required this.quote,
    required this.theme,
  });

  final Quote quote;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _AmountLabel(
          label: 'Total',
          value: CurrencyUtils.format(quote.totalCents),
          bold: true,
        ),
        _AmountLabel(
          label: 'Reste à charge',
          value: CurrencyUtils.format(quote.patientShareCents),
          bold: true,
        ),
      ],
    );
  }
}

class _AmountLabel extends StatelessWidget {
  const _AmountLabel({
    required this.label,
    required this.value,
    required this.bold,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
