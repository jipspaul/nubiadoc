import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_page.dart' show formatEuros, mapQuoteStatus;
import 'devis_state.dart';

/// Détail d'un devis côté secrétariat.
/// Cloisonnement : aucun champ clinique (motif, notes médicales) affiché.
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
            return NubiaErrorWidget(
              message: state.message,
              onRetry: () => context
                  .read<DevisBloc>()
                  .add(DevisDetailLoadRequested(widget.id)),
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

  StatusPillVariant _statusVariant(CabinetQuoteStatus status) {
    switch (status) {
      case CabinetQuoteStatus.draft:
        return StatusPillVariant.info;
      case CabinetQuoteStatus.sent:
        return StatusPillVariant.warning;
      case CabinetQuoteStatus.signed:
        return StatusPillVariant.success;
      case CabinetQuoteStatus.expired:
      case CabinetQuoteStatus.cancelled:
        return StatusPillVariant.error;
    }
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final hasDates = quote.expiresAt != null || quote.signedAt != null;
    final hasItems = quote.items != null && quote.items!.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AmountHeader(
          label: 'Total du plan de soins',
          amount: formatEuros(quote.totalCents),
          caption: quote.patientName,
          remainingLabel: 'Part patient',
          remainingAmount: formatEuros(quote.patientShareCents),
          remainingCaption: 'Reste à charge',
        ),
        const SizedBox(height: 16),
        Center(
          child: StatusPill(
            label: _statusLabel(quote.status),
            variant: _statusVariant(quote.status),
          ),
        ),
        if (hasDates) ...[
          const SizedBox(height: 16),
          NubiaCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (quote.expiresAt != null)
                  _DateRow(
                    label: 'Expire le',
                    value: _formatDate(quote.expiresAt!),
                  ),
                if (quote.expiresAt != null && quote.signedAt != null)
                  const SizedBox(height: 8),
                if (quote.signedAt != null)
                  _DateRow(
                    label: 'Signé le',
                    value: _formatDate(quote.signedAt!),
                  ),
              ],
            ),
          ),
        ],
        if (hasItems) ...[
          const SizedBox(height: 16),
          QuoteCard(
            title: 'Détail des actes',
            status: mapQuoteStatus(quote.status),
            lines: [
              for (final item in quote.items!)
                QuoteLine(
                  label: item.label,
                  amount: formatEuros(item.totalCents),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
