import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'pharmacy_quotes_bloc.dart';

/// Devis d'officine reçus par le patient — consultation + décision (#6580 :
/// jusqu'ici l'API notifiait un devis « à signer » sans qu'aucun écran patient
/// ne permette de le voir, l'accepter ou le refuser).
class PharmacyQuotesPage extends StatelessWidget {
  const PharmacyQuotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PharmacyQuotesBloc, PharmacyQuotesState>(
      builder: (context, state) {
        if (state is PharmacyQuotesLoading) {
          return const Center(
            key: Key('pharmacy_quotes_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is PharmacyQuotesError) {
          return NubiaErrorWidget(
            key: const Key('pharmacy_quotes_error'),
            message: state.message,
            onRetry: () => context
                .read<PharmacyQuotesBloc>()
                .add(const PharmacyQuotesRequested()),
          );
        }
        final loaded = state as PharmacyQuotesLoaded;
        if (loaded.quotes.isEmpty) {
          return const NubiaEmptyState(
            key: Key('pharmacy_quotes_empty'),
            icon: Icons.receipt_long_outlined,
            title: 'Aucun devis pharmacie',
            subtitle:
                'Les devis envoyés par votre pharmacie apparaîtront ici.',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => context
              .read<PharmacyQuotesBloc>()
              .add(const PharmacyQuotesRequested()),
          child: ListView.separated(
            key: const Key('pharmacy_quotes_list'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            itemCount: loaded.quotes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _PharmacyQuoteCard(
              quote: loaded.quotes[i],
              deciding: loaded.decidingId == loaded.quotes[i].id,
              errorMessage:
                  loaded.erroredId == loaded.quotes[i].id
                      ? loaded.errorMessage
                      : null,
            ),
          ),
        );
      },
    );
  }
}

class _PharmacyQuoteCard extends StatelessWidget {
  const _PharmacyQuoteCard({
    required this.quote,
    required this.deciding,
    required this.errorMessage,
  });

  final PharmacyQuote quote;
  final bool deciding;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = _statusStyle(quote.status);

    return NubiaCard(
      key: Key('pharmacy_quote_item_${quote.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  quote.pharmacyName ?? 'Votre pharmacie',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(label: style.label, variant: style.variant),
            ],
          ),
          const SizedBox(height: 10),
          for (final item in quote.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${item.quantity} × ${item.label}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            formatQuoteCents(quote.totalCents),
            style: theme.textTheme.headlineSmall?.copyWith(
              color: cs.onSurface,
              fontFeatures: tabularFigures,
            ),
          ),
          if (quote.isDecidable) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: NubiaButton(
                    key: Key('pharmacy_quote_accept_${quote.id}'),
                    label: 'Accepter',
                    icon: Icons.check,
                    onPressed: deciding
                        ? null
                        : () => context.read<PharmacyQuotesBloc>().add(
                              PharmacyQuoteDecisionRequested(
                                quote.id,
                                accept: true,
                              ),
                            ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: NubiaButton(
                    key: Key('pharmacy_quote_refuse_${quote.id}'),
                    label: 'Refuser',
                    icon: Icons.close,
                    variant: NubiaButtonVariant.secondary,
                    onPressed: deciding
                        ? null
                        : () => context.read<PharmacyQuotesBloc>().add(
                              PharmacyQuoteDecisionRequested(
                                quote.id,
                                accept: false,
                              ),
                            ),
                  ),
                ),
              ],
            ),
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                key: Key('pharmacy_quote_error_${quote.id}'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.error),
              ),
            ],
          ],
        ],
      ),
    );
  }

  ({String label, StatusPillVariant variant}) _statusStyle(
    PharmacyQuoteStatus status,
  ) {
    return switch (status) {
      PharmacyQuoteStatus.draft => (
          label: 'Brouillon',
          variant: StatusPillVariant.info,
        ),
      PharmacyQuoteStatus.sent => (
          label: 'À signer',
          variant: StatusPillVariant.warning,
        ),
      PharmacyQuoteStatus.accepted => (
          label: 'Accepté',
          variant: StatusPillVariant.success,
        ),
      PharmacyQuoteStatus.refused => (
          label: 'Refusé',
          variant: StatusPillVariant.error,
        ),
      PharmacyQuoteStatus.expired => (
          label: 'Expiré',
          variant: StatusPillVariant.error,
        ),
    };
  }
}
