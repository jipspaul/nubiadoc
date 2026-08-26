import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'cabinet_payouts_bloc.dart';
import 'cabinet_payouts_event.dart';
import 'cabinet_payouts_state.dart';

/// Page complète (route dédiée) — même découpage que `CabinetStatsPage`.
class CabinetPayoutsPage extends StatelessWidget {
  const CabinetPayoutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('cabinet_payouts_scaffold'),
      appBar: AppBar(
        title: const Text('Rapprochement bancaire'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<CabinetPayoutsBloc>()
                .add(const CabinetPayoutsLoadRequested()),
          ),
        ],
      ),
      body: const CabinetPayoutsBody(),
    );
  }
}

String _euros(int cents) => '${(cents / 100).toStringAsFixed(2)} €';

String _providerLabel(PayoutProvider provider) => switch (provider) {
      PayoutProvider.stripe => 'Stripe',
      PayoutProvider.gocardless => 'GoCardless',
    };

String _pad2(int n) => n.toString().padLeft(2, '0');

String _formatDate(DateTime d) => '${_pad2(d.day)}/${_pad2(d.month)}/${d.year}';

/// Paiement interne non rapprochable par le prestataire dont le montant
/// égale exactement l'écart (#5110) — signale une « piste probable » sans
/// jamais rapprocher automatiquement quoi que ce soit.
InternalPayment? _probableLead(CabinetPayout payout) {
  for (final payment in payout.internalPayments) {
    if (!payment.reconcilableByProvider &&
        payment.amountCents == payout.differenceCents.abs()) {
      return payment;
    }
  }
  return null;
}

/// Corps de l'écran — consommable dans `ProShell.bodyBuilder`.
class CabinetPayoutsBody extends StatelessWidget {
  const CabinetPayoutsBody({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CabinetPayoutsBloc, CabinetPayoutsState>(
      builder: (context, state) {
        return switch (state) {
          CabinetPayoutsLoading() => const Center(
              key: Key('cabinet_payouts_loading'),
              child: CircularProgressIndicator(),
            ),
          CabinetPayoutsError(:final message) => NubiaErrorWidget(
              key: const Key('cabinet_payouts_error'),
              message: message,
              onRetry: () => context
                  .read<CabinetPayoutsBloc>()
                  .add(const CabinetPayoutsLoadRequested()),
            ),
          CabinetPayoutsLoaded(:final payouts, :final selectedPayoutId) =>
            payouts.isEmpty
                ? const NubiaEmptyState(
                    key: Key('cabinet_payouts_empty'),
                    icon: Icons.account_balance_outlined,
                    title: 'Aucun virement',
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _PayoutsList(
                          payouts: payouts,
                          selectedPayoutId: selectedPayoutId,
                        ),
                      ),
                      if (selectedPayoutId != null)
                        SizedBox(
                          width: 320,
                          child: _PayoutDetailPanel(
                            payout: payouts.firstWhere(
                              (p) => p.id == selectedPayoutId,
                            ),
                          ),
                        ),
                    ],
                  ),
        };
      },
    );
  }
}

class _PayoutsList extends StatelessWidget {
  const _PayoutsList({required this.payouts, this.selectedPayoutId});

  final List<CabinetPayout> payouts;
  final String? selectedPayoutId;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('cabinet_payouts_list'),
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Virements Stripe/GoCardless (données de démonstration — aucun '
          'compte connecté) rapprochés aux paiements internes enregistrés '
          'le même jour.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 16),
        for (final payout in payouts) ...[
          _PayoutCard(
            payout: payout,
            selected: payout.id == selectedPayoutId,
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _PayoutCard extends StatelessWidget {
  const _PayoutCard({required this.payout, required this.selected});

  final CabinetPayout payout;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final reconciled =
        payout.reconciliationStatus == PayoutReconciliationStatus.reconciled;
    void onTap() => context
        .read<CabinetPayoutsBloc>()
        .add(CabinetPayoutSelected(payout.id));
    return GestureDetector(
      onTap: onTap,
      child: NubiaCard(
        key: Key('payout_${payout.id}'),
        state: selected ? NubiaCardState.selected : NubiaCardState.interactive,
        onTap: selected ? null : onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_providerLabel(payout.provider)} · ${payout.id}',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                NubiaBadge.label(
                  key: const Key('payout_status_badge'),
                  label: reconciled ? 'Rapproché' : 'À vérifier',
                  variant: reconciled
                      ? NubiaBadgeVariant.success
                      : NubiaBadgeVariant.error,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Virement le ${_formatDate(payout.arrivalDate)}'),
            Text('Montant du virement : ${_euros(payout.amountCents)}'),
            Text(
              'Paiements internes trouvés : '
              '${_euros(payout.internalPaymentsTotalCents)}',
            ),
            if (!reconciled) ...[
              const SizedBox(height: 4),
              Text(
                'Écart : ${_euros(payout.differenceCents)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Volet de détail d'un virement sélectionné — pied de volet : deux actions
/// de résolution de l'écart (#5111), marquer rapproché ou signaler au
/// comptable.
class _PayoutDetailPanel extends StatelessWidget {
  const _PayoutDetailPanel({required this.payout});

  final CabinetPayout payout;

  @override
  Widget build(BuildContext context) {
    final reconciled =
        payout.reconciliationStatus == PayoutReconciliationStatus.reconciled;
    final probableLead = _probableLead(payout);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context).extension<NubiaTokens>()!.borderSubtle,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_providerLabel(payout.provider)} · ${payout.id}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  key: const Key('payout_detail_close'),
                  tooltip: 'Fermer',
                  icon: const Icon(Icons.close),
                  onPressed: () => context
                      .read<CabinetPayoutsBloc>()
                      .add(CabinetPayoutSelected(payout.id)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Virement le ${_formatDate(payout.arrivalDate)}'),
                    Text(
                      'Montant du virement : ${_euros(payout.amountCents)}',
                    ),
                    Text(
                      'Paiements internes trouvés : '
                      '${_euros(payout.internalPaymentsTotalCents)}',
                    ),
                    if (!reconciled) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Écart : ${_euros(payout.differenceCents)}',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    if (probableLead != null) ...[
                      const SizedBox(height: 12),
                      _ProbableLeadCard(payout: payout, lead: probableLead),
                    ],
                    if (payout.internalPayments.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _InternalPaymentsSection(
                        payments: payout.internalPayments,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            NubiaButton(
              key: const Key('payout_action_flag_accountant'),
              label: 'Signaler au comptable',
              variant: NubiaButtonVariant.secondary,
              onPressed: () {
                context
                    .read<CabinetPayoutsBloc>()
                    .add(CabinetPayoutFlaggedToAccountant(payout.id));
                NubiaSnackbar.show(
                  context: context,
                  message: 'Signalé au comptable.',
                );
              },
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: NubiaButton(
                key: const Key('payout_action_mark_reconciled'),
                label: 'Marquer comme rapproché',
                icon: Icons.check,
                onPressed: () => context
                    .read<CabinetPayoutsBloc>()
                    .add(CabinetPayoutMarkedReconciled(payout.id)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Encart « Piste probable » (#5110) : signale un paiement non rapprochable
/// par le prestataire (espèces, chèque…) dont le montant égale exactement
/// l'écart. Purement indicatif — aucun rapprochement automatique, la
/// décision reste humaine (boutons du pied de volet, #5111).
class _ProbableLeadCard extends StatelessWidget {
  const _ProbableLeadCard({required this.payout, required this.lead});

  final CabinetPayout payout;
  final InternalPayment lead;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<NubiaTokens>()!;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      key: const Key('payout_probable_lead'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NubiaColors.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, size: 18, color: tokens.warningFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: textTheme.bodySmall?.copyWith(color: tokens.warningFg),
                children: [
                  const TextSpan(
                    text: 'Piste probable : ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: 'le paiement en ${lead.methodLabel} de '
                        '${NubiaMoney.formatCents(lead.amountCents)} ne '
                        'transite pas par ${_providerLabel(payout.provider)} '
                        "— il explique exactement l'écart. À rapprocher de "
                        'la caisse, pas du virement.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Liste « Paiements internes du jour » (#5109) : chaque encaissement
/// interne du jour, en signalant ceux qui ne transitent pas par le
/// prestataire (espèces/chèque). Purement informatif — aucun rapprochement
/// automatique, données et ordre proviennent tels quels du domaine.
class _InternalPaymentsSection extends StatelessWidget {
  const _InternalPaymentsSection({required this.payments});

  final List<InternalPayment> payments;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      key: const Key('payout_internal_payments_section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Paiements internes du jour',
                style: textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            NubiaBadge.count(
              key: const Key('payout_internal_payments_count'),
              count: payments.length,
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final payment in payments) ...[
          _InternalPaymentRow(payment: payment),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _InternalPaymentRow extends StatelessWidget {
  const _InternalPaymentRow({required this.payment});

  final InternalPayment payment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final mutedColor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NubiaAvatar(initials: _initials(payment.patientName), radius: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                payment.patientName,
                style: textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${payment.methodLabel} · ${payment.time}',
                style: textTheme.bodySmall?.copyWith(color: mutedColor),
              ),
              if (!payment.reconcilableByProvider)
                Text(
                  'non rapprochable',
                  style: textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          NubiaMoney.formatCents(payment.amountCents),
          style: textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Initiales (ex. « Camille Moreau » → « CM ») — même règle que
/// `patients_page.dart::_initials`.
String _initials(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
