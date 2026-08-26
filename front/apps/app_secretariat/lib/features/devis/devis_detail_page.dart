import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'devis_bloc.dart';
import 'devis_event.dart';
import 'devis_page.dart' show mapQuoteStatus;
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
      body: BlocConsumer<DevisBloc, DevisState>(
        listenWhen: (previous, current) => current is DevisSendFailure,
        listener: (context, state) {
          if (state is DevisSendFailure) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  key: const Key('devis_send_error_snackbar'),
                  content: Text(
                    state.message.isEmpty ? 'Envoi impossible.' : state.message,
                  ),
                ),
              );
          }
        },
        builder: (context, state) {
          if (state is DevisDetailLoaded) {
            return _DevisDetailBody(quote: state.quote);
          }
          if (state is DevisSendInProgress) {
            return _DevisDetailBody(quote: state.quote, sending: true);
          }
          // Échec d'envoi : on reste sur le détail pour permettre un nouvel essai.
          if (state is DevisSendFailure) {
            return _DevisDetailBody(quote: state.quote);
          }
          if (state is DevisSent) {
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
          return const _DevisDetailSkeleton();
        },
      ),
    );
  }
}

/// Squelette de chargement du détail d'un devis, calqué sur le rythme des
/// sections de [_DevisDetailBody] (en-tête montant + carte de lignes).
class _DevisDetailSkeleton extends StatelessWidget {
  const _DevisDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('devis_detail_skeleton'),
      padding: const EdgeInsets.all(16),
      children: const [
        NubiaSkeletonLoader(height: 96, borderRadius: 16),
        SizedBox(height: 16),
        Center(
          child: NubiaSkeletonLoader(height: 22, width: 90, borderRadius: 999),
        ),
        SizedBox(height: 16),
        NubiaCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: NubiaSkeletonLoader(height: 18, width: 140),
                  ),
                  SizedBox(width: 12),
                  NubiaSkeletonLoader(
                    height: 22,
                    width: 76,
                    borderRadius: 999,
                  ),
                ],
              ),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: NubiaSkeletonLoader(height: 12, width: 90)),
                  SizedBox(width: 12),
                  NubiaSkeletonLoader(height: 14, width: 64),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: NubiaSkeletonLoader(height: 12, width: 90)),
                  SizedBox(width: 12),
                  NubiaSkeletonLoader(height: 14, width: 64),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DevisDetailBody extends StatelessWidget {
  const _DevisDetailBody({required this.quote, this.sending = false});

  final CabinetQuote quote;
  final bool sending;

  String _statusLabel(CabinetQuoteStatus status) {
    switch (status) {
      case CabinetQuoteStatus.draft:
        return 'Brouillon';
      case CabinetQuoteStatus.sent:
        return 'Envoyé';
      case CabinetQuoteStatus.signed:
        return 'Signé';
      case CabinetQuoteStatus.paid:
        return 'Payé';
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
      case CabinetQuoteStatus.paid:
        return StatusPillVariant.success;
      case CabinetQuoteStatus.expired:
        return StatusPillVariant.error;
      case CabinetQuoteStatus.cancelled:
        return StatusPillVariant.neutral;
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
          label: 'Reste à charge patient · sur '
              '${NubiaMoney.formatCents(quote.totalCents)}',
          amount: NubiaMoney.formatCents(quote.patientShareCents),
          caption: quote.patientName,
        ),
        // Ventilation AMO/AMC (#5091) : même calcul et même vocabulaire que
        // l'app Patient (VentilationBar, packages/nubia_design_system).
        // Omise si le back n'a pas renvoyé les lignes du devis.
        if (hasItems) ...[
          const SizedBox(height: 16),
          VentilationBar(
            amoCents: quote.items!.amoShareTotalCents,
            amcCents: quote.items!.amcShareTotalCents,
            racCents: quote.patientShareCents,
            racLabel: 'Reste à charge',
          ),
        ],
        const SizedBox(height: 16),
        Center(
          child: StatusPill(
            label: _statusLabel(quote.status),
            variant: _statusVariant(quote.status),
          ),
        ),
        // #4537 : brouillon consultable sans action = cul-de-sac pour la
        // secrétaire. Le back autorise déjà secretary+ à envoyer.
        if (quote.status == CabinetQuoteStatus.draft) ...[
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('btn_send_devis_secretariat'),
            label: 'Envoyer au patient',
            icon: Icons.send_outlined,
            size: NubiaButtonSize.lg,
            isLoading: sending,
            onPressed: sending
                ? null
                : () =>
                    context.read<DevisBloc>().add(DevisSendRequested(quote.id)),
          ),
        ],
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
                  amount: NubiaMoney.formatCents(item.totalCents),
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
