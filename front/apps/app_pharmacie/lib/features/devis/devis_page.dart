import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'quote_delay.dart';

/// Devis d'officine — corps de la destination « Devis ».
class PharmacyDevisView extends StatelessWidget {
  const PharmacyDevisView({super.key});

  static const _labels = {
    PharmacyQuoteStatus.draft: 'Brouillon',
    PharmacyQuoteStatus.sent: 'Envoyé',
    PharmacyQuoteStatus.accepted: 'Accepté',
    PharmacyQuoteStatus.refused: 'Refusé',
    PharmacyQuoteStatus.expired: 'Expiré',
  };

  static const _variants = {
    PharmacyQuoteStatus.draft: StatusPillVariant.info,
    PharmacyQuoteStatus.sent: StatusPillVariant.warning,
    PharmacyQuoteStatus.accepted: StatusPillVariant.success,
    PharmacyQuoteStatus.refused: StatusPillVariant.error,
    PharmacyQuoteStatus.expired: StatusPillVariant.error,
  };

  static String formatCents(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PharmacyDevisBloc, PharmacyDevisState>(
      builder: (context, state) {
        switch (state) {
          case PharmacyDevisLoading():
            return const Center(child: CircularProgressIndicator());
          case PharmacyDevisError(:final message):
            return NubiaErrorWidget(
              message: message,
              onRetry: () => context
                  .read<PharmacyDevisBloc>()
                  .add(const PharmacyDevisLoadRequested()),
            );
          case PharmacyDevisLoaded(:final quotes, :final sendingId):
            if (quotes.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucun devis',
                subtitle: 'Créez un devis depuis le détail d\'une commande.',
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: quotes.length,
              itemBuilder: (context, index) {
                final quote = quotes[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _QuoteCard(
                    quote: quote,
                    sending: sendingId == quote.id,
                  ),
                );
              },
            );
        }
      },
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.sending});

  final PharmacyQuote quote;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<NubiaTokens>()!;
    final delay = quoteDelayOf(quote);
    final delayColor = switch (delay.tone) {
      QuoteDelayTone.neutral => tokens.textTertiary,
      QuoteDelayTone.soon => tokens.warningFg,
      QuoteDelayTone.late => tokens.dangerFg,
    };
    return NubiaCard(
      key: Key('quote_${quote.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quote.patientDisplayName ?? 'Patient',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      delay.label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: delayColor,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: PharmacyDevisView._labels[quote.status]!,
                variant: PharmacyDevisView._variants[quote.status]!,
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final item in quote.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '• ${item.quantity} × ${item.label}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    PharmacyDevisView.formatCents(item.totalCents),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Total : ${PharmacyDevisView.formatCents(quote.totalCents)}',
            style: theme.textTheme.titleSmall,
          ),
          if (quote.status == PharmacyQuoteStatus.draft) ...[
            const SizedBox(height: 12),
            NubiaButton(
              key: Key('quote_send_${quote.id}'),
              label: 'Envoyer au patient',
              isLoading: sending,
              onPressed: sending
                  ? null
                  : () => context
                      .read<PharmacyDevisBloc>()
                      .add(PharmacyDevisSendRequested(quote.id)),
            ),
          ],
        ],
      ),
    );
  }
}
