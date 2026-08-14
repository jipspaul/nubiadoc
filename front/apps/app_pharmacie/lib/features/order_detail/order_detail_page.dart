import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart' as core;
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../devis/widgets/quote_composer_sheet.dart';
import 'order_detail_bloc.dart';
import 'order_detail_event.dart';
import 'order_detail_state.dart';
import 'widgets/order_status_stepper.dart';
import 'widgets/pickup_info_card.dart';
import 'widgets/prescription_lines_panel.dart';

/// Détail d'une commande : infos de retrait, PDF d'ordonnance et action de
/// transition contextuelle (pilotée par [PharmacyOrderStatus.canTransitionTo] —
/// le serveur reste l'autorité, 409 remonté en erreur).
class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<OrderDetailBloc>(
      create: (_) => GetIt.instance<OrderDetailBloc>()
        ..add(OrderDetailLoadRequested(orderId)),
      child: const OrderDetailBody(),
    );
  }
}

/// Corps de l'écran détail — public pour les tests widget.
class OrderDetailBody extends StatelessWidget {
  const OrderDetailBody({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commande'),
        leading: BackButton(
          key: const Key('order_detail_back'),
          onPressed: () => context.go('/'),
        ),
      ),
      body: BlocConsumer<OrderDetailBloc, OrderDetailState>(
        listener: (context, state) {
          if (state is OrderDetailDocumentReady) {
            core.openDocumentUrl(state.url);
          }
        },
        builder: (context, state) {
          switch (state) {
            case OrderDetailLoading():
              return const Center(child: CircularProgressIndicator());
            case OrderDetailError(:final message):
              return NubiaErrorWidget(message: message);
            case OrderDetailLoaded(
                :final order,
                :final items,
                :final actionInProgress,
                :final preparedLineIndices
              ):
              return _buildLoaded(
                context,
                order,
                items,
                actionInProgress,
                preparedLineIndices,
              );
            case OrderDetailDocumentReady(:final order):
              return _buildLoaded(context, order, const [], false, const {});
          }
        },
      ),
    );
  }

  /// Seuil (px) à partir duquel les deux volets tiennent côte à côte
  /// (cible tablette/desktop, ex. tablette 1258×834 paysage).
  static const double _twoPaneBreakpoint = 900;

  /// Largeur fixe du volet droit (exécution) sur cible large.
  static const double _executionPaneWidth = 436;

  Widget _buildLoaded(
    BuildContext context,
    PharmacyOrder order,
    List<PrescriptionItem> items,
    bool actionInProgress,
    Set<int> preparedLineIndices,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isTwoPane = constraints.maxWidth >= _twoPaneBreakpoint;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrderStatusStepper(status: order.status),
              const SizedBox(height: 16),
              isTwoPane
                  ? IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _buildReadPane(
                                context, order, items, preparedLineIndices),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            width: _executionPaneWidth,
                            padding: const EdgeInsets.only(left: 16),
                            decoration: BoxDecoration(
                              color: NubiaColors.n0,
                              border: Border(
                                left: BorderSide(
                                  color: Theme.of(context)
                                          .extension<NubiaTokens>()
                                          ?.borderSubtle ??
                                      NubiaColors.n200,
                                ),
                              ),
                            ),
                            child: _buildExecutionPane(context, order, items,
                                actionInProgress, preparedLineIndices),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildReadPane(
                            context, order, items, preparedLineIndices),
                        const SizedBox(height: 24),
                        _buildExecutionPane(context, order, items,
                            actionInProgress, preparedLineIndices),
                      ],
                    ),
            ],
          ),
        );
      },
    );
  }

  /// Volet gauche — ce qui se lit (l'ordonnance).
  Widget _buildReadPane(
    BuildContext context,
    PharmacyOrder order,
    List<PrescriptionItem> items,
    Set<int> preparedLineIndices,
  ) {
    final bloc = context.read<OrderDetailBloc>();
    final canTogglePrepared = order.status == PharmacyOrderStatus.preparing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PickupInfoCard(order: order),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 16),
          PrescriptionLinesPanel(
            items: items,
            onOpenDocument: () =>
                bloc.add(const OrderDetailDocumentRequested()),
            preparedLineIndices: preparedLineIndices,
            onLinePreparedChanged: canTogglePrepared
                ? (index, _) =>
                    bloc.add(OrderDetailLinePreparedToggled(index))
                : null,
          ),
        ],
      ],
    );
  }

  /// Volet droit — ce qui s'exécute (préparation, scan, encaissement).
  Widget _buildExecutionPane(
    BuildContext context,
    PharmacyOrder order,
    List<PrescriptionItem> items,
    bool actionInProgress,
    Set<int> preparedLineIndices,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NubiaButton(
          key: const Key('order_detail_create_quote'),
          label: 'Créer un devis',
          variant: NubiaButtonVariant.secondary,
          onPressed: () => showQuoteComposerSheet(context, orderId: order.id),
        ),
        const SizedBox(height: 24),
        _ContextualAction(
          order: order,
          inProgress: actionInProgress,
          totalLines: items.length,
          preparedLines: preparedLineIndices.length,
        ),
        if (order.hasBillingSummary) ...[
          const SizedBox(height: 24),
          _BillingSummaryCard(order: order),
        ],
      ],
    );
  }
}

/// Bloc facturation (pied du volet droit) : Montant total, part AMO, part
/// AMC, à encaisser — même vocabulaire et même formatage que l'app Patient
/// (helper `formatQuoteCents` partagé, cf. #4063/#4888). N'apparaît que si
/// le back a renseigné la ventilation ([PharmacyOrder.hasBillingSummary]).
class _BillingSummaryCard extends StatelessWidget {
  const _BillingSummaryCard({required this.order});

  final PharmacyOrder order;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tokens = theme.extension<NubiaTokens>()!;

    return NubiaCard(
      key: const Key('order_billing_summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BillingRow(
            label: 'Montant total',
            amountCents: order.billingTotalCents!,
          ),
          const SizedBox(height: 8),
          _BillingRow(
            label: 'Part Assurance Maladie (AMO)',
            amountCents: -order.billingAmoShareCents!,
          ),
          const SizedBox(height: 8),
          _BillingRow(
            label: 'Part mutuelle (AMC)',
            amountCents: -order.billingAmcShareCents!,
          ),
          const SizedBox(height: 12),
          Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'À encaisser',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: cs.onSurface),
                ),
              ),
              Text(
                formatQuoteCents(order.billingPatientShareCents!),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabularFigures,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ligne « libellé — montant » du bloc facturation.
class _BillingRow extends StatelessWidget {
  const _BillingRow({required this.label, required this.amountCents});

  final String label;
  final int amountCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        Text(
          formatQuoteCents(amountCents),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurface,
            fontFeatures: tabularFigures,
          ),
        ),
      ],
    );
  }
}

/// Bouton d'action unique selon le statut (aucun pour un état terminal).
class _ContextualAction extends StatelessWidget {
  const _ContextualAction({
    required this.order,
    required this.inProgress,
    this.totalLines = 0,
    this.preparedLines = 0,
  });

  final PharmacyOrder order;
  final bool inProgress;

  /// Nombre total de lignes d'ordonnance — alimente le compteur « X sur N
  /// préparées » qui conditionne preparing → ready.
  final int totalLines;

  /// Nombre de lignes cochées « préparée ».
  final int preparedLines;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<OrderDetailBloc>();
    switch (order.status) {
      case PharmacyOrderStatus.received:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NubiaButton(
              key: const Key('order_action_accept'),
              label: 'Commencer la préparation',
              isLoading: inProgress,
              onPressed: inProgress
                  ? null
                  : () => bloc.add(const OrderDetailAcceptRequested()),
            ),
            const SizedBox(height: 24),
            Center(
              child: _RejectLink(
                key: const Key('order_action_reject'),
                enabled: !inProgress,
                onPressed: () => _askRejectReason(context, bloc),
              ),
            ),
          ],
        );
      case PharmacyOrderStatus.preparing:
        final allPrepared = totalLines == 0 || preparedLines >= totalLines;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (totalLines > 0) ...[
              Text(
                key: const Key('order_ready_progress'),
                '$preparedLines sur $totalLines préparées',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .extension<NubiaTokens>()
                          ?.textTertiary,
                    ),
              ),
              const SizedBox(height: 8),
            ],
            NubiaButton(
              key: const Key('order_action_ready'),
              label: 'Marquer prête',
              isLoading: inProgress,
              onPressed: inProgress || !allPrepared
                  ? null
                  : () => bloc.add(const OrderDetailReadyRequested()),
            ),
          ],
        );
      case PharmacyOrderStatus.ready:
        return NubiaButton(
          key: const Key('order_action_scan'),
          label: 'Scanner le retrait',
          onPressed: () => context.go('/orders/${order.id}/pickup'),
        );
      case PharmacyOrderStatus.pickedUp:
      case PharmacyOrderStatus.rejected:
      case PharmacyOrderStatus.cancelled:
        return const SizedBox.shrink();
    }
  }

  Future<void> _askRejectReason(
    BuildContext context,
    OrderDetailBloc bloc,
  ) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Refuser la commande'),
        content: NubiaTextField(
          key: const Key('reject_reason_field'),
          controller: controller,
          label: 'Motif (obligatoire)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            key: const Key('reject_confirm'),
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Refuser'),
          ),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) {
      bloc.add(OrderDetailRejectRequested(reason));
    }
  }
}

/// Lien discret « Refuser la commande » — action exigeant un motif et menant
/// à un état terminal (`rejected`), volontairement éloignée du geste
/// principal plutôt qu'un [NubiaButton] pleine largeur.
class _RejectLink extends StatelessWidget {
  const _RejectLink({
    super.key,
    required this.enabled,
    required this.onPressed,
  });

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dangerFg = Theme.of(context).extension<NubiaTokens>()?.dangerFg ??
        NubiaColors.dangerFg;
    final color = enabled ? dangerFg : dangerFg.withValues(alpha: 0.4);
    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              'Refuser la commande',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}
