import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'financial_bloc.dart';
import 'financial_event.dart';
import 'financial_state.dart';

/// Wedge financier : liste de devis → détail → signature Yousign → paiement acompte.
///
/// Doit être placé sous un [BlocProvider<FinancialBloc>] (fourni par le router
/// ou le parent).
class FinancialPage extends StatelessWidget {
  const FinancialPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FinancialBloc, FinancialState>(
      builder: (context, state) {
        if (state is FinancialInitial || state is FinancialLoading) {
          return const Center(
            key: Key('financial_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is FinancialError) {
          return _ErrorView(key: const Key('financial_error'), state: state);
        }
        if (state is FinancialLoaded) {
          return _QuoteListView(state: state);
        }
        if (state is FinancialQuoteDetail) {
          return _QuoteDetailView(state: state);
        }
        if (state is FinancialSignatureInProgress) {
          return _SignatureView(state: state);
        }
        if (state is FinancialPaymentInProgress) {
          return const Center(
            key: Key('financial_payment_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is FinancialPaymentSuccess) {
          return _PaymentSuccessView(state: state);
        }
        return const SizedBox.shrink();
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _QuoteListView extends StatelessWidget {
  const _QuoteListView({required this.state});

  final FinancialLoaded state;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async =>
          context.read<FinancialBloc>().add(const FinancialLoadRequested()),
      child: state.quotes.isEmpty
          ? LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: constraints.maxHeight,
                  child: const Center(
                    key: Key('financial_empty'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48),
                        SizedBox(height: 12),
                        Text('Aucun devis en attente.'),
                      ],
                    ),
                  ),
                ),
              ),
            )
          : ListView.builder(
              key: const Key('financial_list'),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: state.quotes.length,
              itemBuilder: (context, i) => _QuoteTile(quote: state.quotes[i]),
            ),
    );
  }
}

// ---------------------------------------------------------------------------

class _QuoteTile extends StatelessWidget {
  const _QuoteTile({required this.quote});

  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('quote_item_${quote.id}'),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        title: Text(quote.practitionerName),
        subtitle: Text(_formatStatus(quote.status)),
        trailing: Text(
          _formatCents(quote.patientShareCents),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        onTap: () => context
            .read<FinancialBloc>()
            .add(FinancialQuoteSelected(quote.id)),
      ),
    );
  }

  String _formatStatus(QuoteStatus status) => switch (status) {
        QuoteStatus.draft => 'Brouillon',
        QuoteStatus.sent => 'En attente de signature',
        QuoteStatus.signed => 'Signé',
        QuoteStatus.expired => 'Expiré',
        QuoteStatus.cancelled => 'Annulé',
      };

  String _formatCents(int cents) {
    final euros = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '$euros €';
  }
}

// ---------------------------------------------------------------------------

class _QuoteDetailView extends StatefulWidget {
  const _QuoteDetailView({required this.state});

  final FinancialQuoteDetail state;

  @override
  State<_QuoteDetailView> createState() => _QuoteDetailViewState();
}

class _QuoteDetailViewState extends State<_QuoteDetailView> {
  late final String _payKey =
      '${widget.state.quote.id}-pay-${DateTime.now().microsecondsSinceEpoch}';

  @override
  Widget build(BuildContext context) {
    final quote = widget.state.quote;
    final canSign = quote.canSign;
    final canPay = quote.status == QuoteStatus.signed && quote.depositCents > 0;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DetailHeader(quote: quote),
                const SizedBox(height: 16),
                Text(
                  'Détail des actes',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...quote.items.map((item) => _LineItemTile(item: item)),
                const SizedBox(height: 16),
                _TotalRow(quote: quote),
              ],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (canSign)
                  FilledButton(
                    key: const Key('btn_sign'),
                    onPressed: () => context
                        .read<FinancialBloc>()
                        .add(const FinancialSignatureRequested()),
                    child: const Text('Signer le devis'),
                  ),
                if (canPay) ...[
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('btn_pay'),
                    onPressed: () => context
                        .read<FinancialBloc>()
                        .add(FinancialPaymentRequested(
                            idempotencyKey: _payKey)),
                    child: const Text('Payer l\'acompte'),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('btn_back'),
                  onPressed: () => context
                      .read<FinancialBloc>()
                      .add(const FinancialBackToList()),
                  child: const Text('Retour à la liste'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(quote.practitionerName,
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          _formatCents(quote.patientShareCents),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatDate(quote.createdAt),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  String _formatCents(int cents) {
    final euros = (cents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return '$euros €';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }
}

class _LineItemTile extends StatelessWidget {
  const _LineItemTile({required this.item});
  final QuoteLineItem item;

  @override
  Widget build(BuildContext context) {
    final euros = (item.patientShareCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(item.label)),
          Text('$euros €',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.quote});
  final Quote quote;

  @override
  Widget build(BuildContext context) {
    final euros =
        (quote.depositCents / 100).toStringAsFixed(2).replaceAll('.', ',');
    return Row(
      children: [
        Expanded(
            child: Text('Acompte demandé',
                style: Theme.of(context).textTheme.titleSmall)),
        Text('$euros €',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _SignatureView extends StatelessWidget {
  const _SignatureView({required this.state});

  final FinancialSignatureInProgress state;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('financial_signature'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              'Signature en cours',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Ouvrez le lien ci-dessous pour signer votre devis.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton(
              key: const Key('btn_confirm_signature'),
              onPressed: () => context
                  .read<FinancialBloc>()
                  .add(const FinancialSignatureCompleted()),
              child: const Text('Confirmer la signature'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _PaymentSuccessView extends StatelessWidget {
  const _PaymentSuccessView({required this.state});

  final FinancialPaymentSuccess state;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('financial_success'),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'Paiement effectué',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Votre acompte a bien été reçu.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            TextButton(
              key: const Key('btn_back_after_success'),
              onPressed: () => context
                  .read<FinancialBloc>()
                  .add(const FinancialBackToList()),
              child: const Text('Retour à mes devis'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({super.key, required this.state});

  final FinancialError state;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 8),
            Text(
              state.message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context
                  .read<FinancialBloc>()
                  .add(const FinancialLoadRequested()),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
