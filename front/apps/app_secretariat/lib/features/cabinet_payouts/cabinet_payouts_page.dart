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
            const Spacer(),
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
