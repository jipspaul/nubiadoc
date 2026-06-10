import 'package:flutter/material.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/presentation/theme/nubia_tokens.dart';

/// Tuile repliable affichant une ligne de devis.
///
/// Affiche le libellé + le reste à charge patient. Développé : répartition
/// Sécu / Mutuelle / Patient.
class QuoteLineItemTile extends StatelessWidget {
  const QuoteLineItemTile({super.key, required this.item});

  final QuoteLineItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;

    return ExpansionTile(
      key: Key('quote_line_${item.id}'),
      tilePadding: const EdgeInsets.symmetric(horizontal: 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              item.toothLabel != null
                  ? '${item.label} (dent ${item.toothLabel})'
                  : item.label,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            _formatCents(item.patientShareCents),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              _ShareRow(
                label: 'Total',
                cents: item.totalCents,
                style: theme.textTheme.bodySmall,
                color: theme.colorScheme.onSurface,
              ),
              _ShareRow(
                label: 'Remb. Sécu',
                cents: item.amoShareCents,
                style: theme.textTheme.bodySmall,
                color: tokens.successFg,
              ),
              _ShareRow(
                label: 'Remb. Mutuelle',
                cents: item.amcShareCents,
                style: theme.textTheme.bodySmall,
                color: tokens.infoFg,
              ),
              _ShareRow(
                label: 'Reste à charge',
                cents: item.patientShareCents,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                color: theme.colorScheme.onSurface,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatCents(int cents) {
    final euros = cents / 100;
    return '${euros.toStringAsFixed(2)} €';
  }
}

class _ShareRow extends StatelessWidget {
  const _ShareRow({
    required this.label,
    required this.cents,
    required this.style,
    required this.color,
  });

  final String label;
  final int cents;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style?.copyWith(color: color)),
          Text(
            '${(cents / 100).toStringAsFixed(2)} €',
            style: style?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
