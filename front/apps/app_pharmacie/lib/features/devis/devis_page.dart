import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'quote_delay.dart';
import 'widgets/devis_kpis.dart';

/// Devis d'officine — corps de la destination « Devis ».
class PharmacyDevisView extends StatefulWidget {
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

  /// `refused` et `expired` partagent le variant `error` : seule l'icône
  /// (et l'action proposée sous la carte) les distingue — un refus est une
  /// décision du patient, une expiration un délai dépassé.
  static const _icons = {
    PharmacyQuoteStatus.refused: Icons.cancel,
    PharmacyQuoteStatus.expired: Icons.event_busy,
  };

  static String formatCents(int cents) =>
      '${(cents / 100).toStringAsFixed(2).replaceAll('.', ',')} €';

  @override
  State<PharmacyDevisView> createState() => _PharmacyDevisViewState();
}

class _PharmacyDevisViewState extends State<PharmacyDevisView> {
  String _query = '';

  List<PharmacyQuote> _filter(List<PharmacyQuote> quotes) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return quotes;
    return quotes
        .where((quote) =>
            (quote.patientDisplayName ?? '').toLowerCase().contains(query) ||
            quote.items
                .any((item) => item.label.toLowerCase().contains(query)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PharmacyDevisBloc, PharmacyDevisState>(
      builder: (context, state) {
        switch (state) {
          case PharmacyDevisLoading():
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  NubiaSkeletonLoader(height: 160, borderRadius: 12),
                  SizedBox(height: 12),
                  NubiaSkeletonLoader(height: 160, borderRadius: 12),
                  SizedBox(height: 12),
                  NubiaSkeletonLoader(height: 160, borderRadius: 12),
                ],
              ),
            );
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
            final filtered = _filter(quotes);
            return Column(
              children: [
                DevisKpiBanner(quotes: quotes),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: 230,
                      child: NubiaSearchBar(
                        key: const Key('devis_search'),
                        hint: 'Patient, article…',
                        onChanged: (value) => setState(() => _query = value),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final quote = filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _QuoteCard(
                          quote: quote,
                          sending: sendingId == quote.id,
                        ),
                      );
                    },
                  ),
                ),
              ],
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
                icon: PharmacyDevisView._icons[quote.status],
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
          ] else if (quote.status == PharmacyQuoteStatus.expired &&
              quote.orderId != null) ...[
            // Occasion manquée (délai dépassé) : un nouveau devis peut être
            // réémis depuis la commande d'origine — contrairement à un
            // refus, qui est une décision terminale du patient.
            const SizedBox(height: 12),
            NubiaButton(
              key: Key('quote_reissue_${quote.id}'),
              label: 'Réémettre',
              icon: Icons.refresh,
              variant: NubiaButtonVariant.secondary,
              onPressed: () => context.go('/orders/${quote.orderId}'),
            ),
          ] else if (quote.status == PharmacyQuoteStatus.refused &&
              quote.orderId != null) ...[
            const SizedBox(height: 12),
            NubiaButton(
              key: Key('quote_view_${quote.id}'),
              label: 'Voir',
              icon: Icons.visibility,
              variant: NubiaButtonVariant.tertiary,
              onPressed: () => context.go('/orders/${quote.orderId}'),
            ),
          ],
        ],
      ),
    );
  }
}
