import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_state.dart';

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
              itemBuilder: (ctx, i) => _DevisTile(
                quote: quotes[i],
                onTap: () => ctx.go('/devis/${quotes[i].id}'),
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

class _DevisTile extends StatelessWidget {
  const _DevisTile({required this.quote, this.onTap});

  final CabinetQuote quote;
  final VoidCallback? onTap;

  String _statusLabel(CabinetQuoteStatus status) {
    switch (status) {
      case CabinetQuoteStatus.draft:
        return 'Brouillon';
      case CabinetQuoteStatus.sent:
        return 'Envoyé';
      case CabinetQuoteStatus.signed:
        return 'Signé';
      case CabinetQuoteStatus.expired:
        return 'Expiré';
      case CabinetQuoteStatus.cancelled:
        return 'Annulé';
    }
  }

  Color _statusColor(CabinetQuoteStatus status) {
    switch (status) {
      case CabinetQuoteStatus.draft:
        return Colors.grey;
      case CabinetQuoteStatus.sent:
        return Colors.blue;
      case CabinetQuoteStatus.signed:
        return Colors.green;
      case CabinetQuoteStatus.expired:
      case CabinetQuoteStatus.cancelled:
        return Colors.red;
    }
  }

  String _formatEuros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: const Icon(Icons.receipt_long_outlined),
      title: Text(quote.patientName),
      subtitle: Text(
        'Total : ${_formatEuros(quote.totalCents)} '
        '— Part patient : ${_formatEuros(quote.patientShareCents)}',
      ),
      trailing: Chip(
        label: Text(
          _statusLabel(quote.status),
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        backgroundColor: _statusColor(quote.status),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

