import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_state.dart';

class DevisDetailPage extends StatefulWidget {
  const DevisDetailPage({super.key, required this.id});

  final String id;

  @override
  State<DevisDetailPage> createState() => _DevisDetailPageState();
}

class _DevisDetailPageState extends State<DevisDetailPage> {
  @override
  void initState() {
    super.initState();
    context.read<DevisBloc>().add(DevisDetailLoadRequested(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Détail devis')),
      body: BlocBuilder<DevisBloc, DevisState>(
        builder: (context, state) {
          if (state is DevisDetailLoaded) {
            return _DevisDetailBody(quote: state.quote);
          }
          if (state is DevisDetailError) {
            return Center(
              child: Text(
                state.message,
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class _DevisDetailBody extends StatelessWidget {
  const _DevisDetailBody({required this.quote});

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

  String _formatEuros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(quote.patientName, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        Chip(label: Text(_statusLabel(quote.status))),
        const SizedBox(height: 16),
        _Row(label: 'Montant total', value: _formatEuros(quote.totalCents)),
        _Row(
          label: 'Part patient',
          value: _formatEuros(quote.patientShareCents),
        ),
        if (quote.expiresAt != null)
          _Row(
            label: 'Expire le',
            value:
                '${quote.expiresAt!.day.toString().padLeft(2, '0')}/${quote.expiresAt!.month.toString().padLeft(2, '0')}/${quote.expiresAt!.year}',
          ),
        if (quote.signedAt != null)
          _Row(
            label: 'Signé le',
            value:
                '${quote.signedAt!.day.toString().padLeft(2, '0')}/${quote.signedAt!.month.toString().padLeft(2, '0')}/${quote.signedAt!.year}',
          ),
        if (quote.items != null && quote.items!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Actes', style: theme.textTheme.titleMedium),
          const Divider(),
          ...quote.items!.map(
            (item) => ListTile(
              title: Text(item.label),
              trailing: Text(_formatEuros(item.totalCents)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value),
        ],
      ),
    );
  }
}
