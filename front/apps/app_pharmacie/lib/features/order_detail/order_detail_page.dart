import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_core/nubia_core.dart' as core;
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'order_detail_bloc.dart';
import 'order_detail_event.dart';
import 'order_detail_state.dart';
import 'widgets/pickup_info_card.dart';

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
            case OrderDetailLoaded(:final order, :final actionInProgress):
              return _buildLoaded(context, order, actionInProgress);
            case OrderDetailDocumentReady(:final order):
              return _buildLoaded(context, order, false);
          }
        },
      ),
    );
  }

  Widget _buildLoaded(
    BuildContext context,
    PharmacyOrder order,
    bool actionInProgress,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PickupInfoCard(order: order),
          const SizedBox(height: 16),
          NubiaButton(
            key: const Key('order_detail_open_document'),
            label: 'Ouvrir l\'ordonnance (PDF)',
            variant: NubiaButtonVariant.secondary,
            onPressed: () => context
                .read<OrderDetailBloc>()
                .add(const OrderDetailDocumentRequested()),
          ),
          const SizedBox(height: 24),
          _ContextualAction(order: order, inProgress: actionInProgress),
        ],
      ),
    );
  }
}

/// Bouton d'action unique selon le statut (aucun pour un état terminal).
class _ContextualAction extends StatelessWidget {
  const _ContextualAction({required this.order, required this.inProgress});

  final PharmacyOrder order;
  final bool inProgress;

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
            const SizedBox(height: 8),
            NubiaButton(
              key: const Key('order_action_reject'),
              label: 'Refuser la commande',
              variant: NubiaButtonVariant.secondary,
              onPressed:
                  inProgress ? null : () => _askRejectReason(context, bloc),
            ),
          ],
        );
      case PharmacyOrderStatus.preparing:
        return NubiaButton(
          key: const Key('order_action_ready'),
          label: 'Marquer prête',
          isLoading: inProgress,
          onPressed: inProgress
              ? null
              : () => bloc.add(const OrderDetailReadyRequested()),
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
