import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_state.dart';

/// Écran "Devis" côté secrétariat — liste des devis du cabinet.
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
class DevisPage extends StatefulWidget {
  const DevisPage({super.key});

  @override
  State<DevisPage> createState() => _DevisPageState();
}

class _DevisPageState extends State<DevisPage> {
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    context.read<DevisBloc>().add(const DevisLoadRequested());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(NubiaL10n.quotes),
        actions: [
          IconButton(
            key: const Key('sort_button'),
            tooltip: _sortAsc ? 'Plus récent d\'abord' : 'Plus ancien d\'abord',
            icon: Icon(
              _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
            ),
            onPressed: () => setState(() => _sortAsc = !_sortAsc),
          ),
          IconButton(
            tooltip: NubiaL10n.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<DevisBloc>().add(const DevisLoadRequested()),
          ),
        ],
      ),
      body: BlocBuilder<DevisBloc, DevisState>(
        builder: (context, state) {
          if (state is DevisLoaded) {
            final quotes = [...state.quotes]..sort(
                (a, b) => _sortAsc
                    ? a.createdAt.compareTo(b.createdAt)
                    : b.createdAt.compareTo(a.createdAt),
              );
            if (quotes.isEmpty) {
              return const NubiaEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Aucun devis',
                subtitle: NubiaL10n.noQuotes,
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: quotes.length,
              itemBuilder: (ctx, i) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _DevisCard(
                  quote: quotes[i],
                  onTap: () => ctx.go('/devis/${quotes[i].id}'),
                ),
              ),
            );
          }
          if (state is DevisError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () =>
                  context.read<DevisBloc>().add(const DevisLoadRequested()),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

/// Formate un montant en centimes vers une chaîne « 350.00 € ».
String formatEuros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

/// Mappe le statut métier ([CabinetQuoteStatus]) vers le statut du composant DS
/// ([QuoteCardStatus]). Le WEDGE DS n'a pas d'état « annulé » : on le rapproche
/// de « refusé » (variante danger, cycle clôturé négativement).
QuoteCardStatus mapQuoteStatus(CabinetQuoteStatus status) {
  switch (status) {
    case CabinetQuoteStatus.draft:
      return QuoteCardStatus.draft;
    case CabinetQuoteStatus.sent:
      return QuoteCardStatus.sent;
    case CabinetQuoteStatus.signed:
      return QuoteCardStatus.signed;
    case CabinetQuoteStatus.expired:
      return QuoteCardStatus.expired;
    case CabinetQuoteStatus.cancelled:
      return QuoteCardStatus.refused;
  }
}

class _DevisCard extends StatelessWidget {
  const _DevisCard({required this.quote, this.onTap});

  final CabinetQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: QuoteCard(
        title: quote.patientName,
        status: mapQuoteStatus(quote.status),
        lines: [
          QuoteLine(label: 'Total', amount: formatEuros(quote.totalCents)),
          QuoteLine(
            label: 'Part patient',
            amount: formatEuros(quote.patientShareCents),
          ),
        ],
      ),
    );
  }
}
