import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
            final quotes = state.quotes;
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
              itemBuilder: (_, i) => _DevisTile(quote: quotes[i]),
            );
          }
          if (state is DevisError) {
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () =>
                  context.read<DevisBloc>().add(const DevisLoadRequested()),
            );
          }
          return const _LoadingView();
        },
      ),
    );
  }
}

class _DevisTile extends StatelessWidget {
  const _DevisTile({required this.quote});

  final CabinetQuote quote;

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

  String _formatEuros(int cents) =>
      '${(cents / 100).toStringAsFixed(2)} €';

  @override
  Widget build(BuildContext context) {
    return ListTile(
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

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: NubiaSkeletonLoader(height: 72),
      ),
    );
  }
}
