import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../financial_bloc.dart';
import '../financial_event.dart';
import '../financial_state.dart';
import 'financial_format_utils.dart';

/// Liste des devis en attente — extrait de `financial_page.dart` (#4061,
/// CLAUDE.md plafond 700 lignes).

class FinancialLoadingView extends StatelessWidget {
  const FinancialLoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    // Skeleton de trois cartes plutôt qu'un spinner nu (§2 principes design).
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: const [
        _QuoteSkeletonCard(),
        SizedBox(height: 12),
        _QuoteSkeletonCard(),
        SizedBox(height: 12),
        _QuoteSkeletonCard(),
      ],
    );
  }
}

class _QuoteSkeletonCard extends StatelessWidget {
  const _QuoteSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const NubiaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: NubiaSkeletonLoader(height: 16, width: 160)),
              SizedBox(width: 12),
              NubiaSkeletonLoader(height: 20, width: 64),
            ],
          ),
          SizedBox(height: 12),
          NubiaSkeletonLoader(height: 28, width: 120),
          SizedBox(height: 10),
          NubiaSkeletonLoader(height: 12, width: 90),
        ],
      ),
    );
  }
}

class QuoteListView extends StatefulWidget {
  const QuoteListView({super.key, required this.state});

  final FinancialLoaded state;

  @override
  State<QuoteListView> createState() => _QuoteListViewState();
}

class _QuoteListViewState extends State<QuoteListView> {
  Completer<void>? _refreshCompleter;

  @override
  Widget build(BuildContext context) {
    return BlocListener<FinancialBloc, FinancialState>(
      listener: (context, state) {
        if (state is FinancialLoaded || state is FinancialError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
      },
      child: RefreshIndicator(
        onRefresh: () {
          _refreshCompleter = Completer<void>();
          context.read<FinancialBloc>().add(const FinancialLoadRequested());
          return _refreshCompleter!.future;
        },
        child: widget.state.quotes.isEmpty
            ? LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height: constraints.maxHeight,
                    child: const NubiaEmptyState(
                      key: Key('financial_empty'),
                      icon: Icons.receipt_long_outlined,
                      title: 'Aucun devis en attente',
                      subtitle:
                          'Vos plans de soins à signer ou à régler apparaîtront ici.',
                    ),
                  ),
                ),
              )
            : ListView.separated(
                key: const Key('financial_list'),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: widget.state.quotes.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, i) =>
                    _QuoteTile(quote: widget.state.quotes[i]),
              ),
      ),
    );
  }
}

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final style = QuoteStatusStyle.of(quote.status);

    // L'API ne renvoie pas toujours de nom de praticien sur la liste : on titre
    // alors par la date du devis.
    final title = quote.practitionerName.isNotEmpty
        ? quote.practitionerName
        : 'Devis du ${formatQuoteDate(quote.createdAt)}';

    return NubiaCard(
      key: Key('quote_item_${quote.id}'),
      state: NubiaCardState.interactive,
      onTap: () =>
          context.read<FinancialBloc>().add(FinancialQuoteSelected(quote.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 12),
              StatusPill(label: style.label, variant: style.variant),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reste à charge',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatQuoteCents(quote.patientShareCents),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: cs.onSurface,
                        fontFeatures: tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatQuoteDate(quote.createdAt),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ],
      ),
    );
  }
}
