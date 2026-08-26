import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'lab_work_orders_bloc.dart';
import 'lab_work_orders_event.dart';
import 'lab_work_orders_state.dart';

/// Ordre de progression (miroir de `STATUS_ORDER`, `api/src/lab_work_orders.rs`,
/// #4148) — sert à la fois au groupement de l'affichage et au calcul du
/// prochain statut proposé par le bouton "Avancer".
const _kStatusOrder = ['sent', 'try_in', 'returned', 'fitted'];

const _kStatusLabels = <String, String>{
  'sent': 'Envoyé au labo',
  'try_in': 'Essayage',
  'returned': 'Retourné',
  'fitted': 'Posé',
};

const _kStatusVariants = <String, StatusPillVariant>{
  'sent': StatusPillVariant.info,
  'try_in': StatusPillVariant.warning,
  'returned': StatusPillVariant.warning,
  'fitted': StatusPillVariant.success,
};

/// Écran « Travaux de laboratoire » côté cabinet (#4149) : bons de travaux
/// prothétiques groupés par statut, avec action d'avancement de statut.
class LabWorkOrdersPage extends StatefulWidget {
  const LabWorkOrdersPage({super.key});

  @override
  State<LabWorkOrdersPage> createState() => _LabWorkOrdersPageState();
}

class _LabWorkOrdersPageState extends State<LabWorkOrdersPage> {
  @override
  void initState() {
    super.initState();
    context.read<LabWorkOrdersBloc>().add(const LabWorkOrdersLoadRequested());
  }

  void _advance(LabWorkOrder order) {
    final index = _kStatusOrder.indexOf(order.status);
    if (index < 0 || index >= _kStatusOrder.length - 1) return;
    context.read<LabWorkOrdersBloc>().add(LabWorkOrdersStatusChangeRequested(
          orderId: order.id,
          status: _kStatusOrder[index + 1],
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travaux de laboratoire'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<LabWorkOrdersBloc>()
                .add(const LabWorkOrdersLoadRequested()),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: NubiaButton(
              key: const Key('lab_work_orders_new_button'),
              label: 'Nouveau bon',
              icon: Icons.add,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                      'Création de bon de travail à venir — bientôt disponible.'),
                ),
              ),
            ),
          ),
        ],
      ),
      body: BlocConsumer<LabWorkOrdersBloc, LabWorkOrdersState>(
        // Seul le rechargement échoué avec des bons déjà affichés déclenche
        // la snackbar : l'erreur du tout premier chargement est déjà portée
        // par `NubiaErrorWidget` plein écran, une seule surface à la fois
        // (#5067).
        listenWhen: (_, s) => s is LabWorkOrdersLoaded && s.errorMessage != null,
        listener: (context, state) {
          if (state is LabWorkOrdersLoaded && state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.errorMessage!)),
            );
          }
        },
        builder: (context, state) {
          switch (state) {
            case LabWorkOrdersLoading():
              return ListView(
                key: const Key('lab_work_orders_loading'),
                padding: const EdgeInsets.all(16),
                children: [
                  for (final status in _kStatusOrder) ...[
                    Padding(
                      key: Key('lab_work_group_skeleton_$status'),
                      padding: const EdgeInsets.only(top: 8, bottom: 8),
                      child: Text(
                        _kStatusLabels[status] ?? status,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    for (var i = 0; i < 2; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: NubiaSkeletonLoader(height: 88, borderRadius: 12),
                      ),
                  ],
                ],
              );
            case LabWorkOrdersError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<LabWorkOrdersBloc>()
                    .add(const LabWorkOrdersLoadRequested()),
              );
            case LabWorkOrdersLoaded(:final orders, :final updatingId):
              if (orders.isEmpty) {
                return const NubiaEmptyState(
                  key: Key('lab_work_orders_empty'),
                  icon: Icons.local_shipping_outlined,
                  title: 'Aucun bon de travail',
                );
              }
              return ListView(
                key: const Key('lab_work_orders_list'),
                padding: const EdgeInsets.all(16),
                children: [
                  for (final status in _kStatusOrder)
                    if (orders.any((o) => o.status == status)) ...[
                      Padding(
                        key: Key('lab_work_group_$status'),
                        padding: const EdgeInsets.only(top: 8, bottom: 8),
                        child: Text(
                          _kStatusLabels[status] ?? status,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      for (final order
                          in orders.where((o) => o.status == status))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NubiaCard(
                            key: Key('lab_work_order_${order.id}'),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(order.labName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          const SizedBox(width: 8),
                                          StatusPill(
                                            key: Key(
                                                'lab_work_order_status_${order.id}'),
                                            label:
                                                _kStatusLabels[order.status] ??
                                                    order.status,
                                            variant: _kStatusVariants[
                                                    order.status] ??
                                                StatusPillVariant.info,
                                          ),
                                        ],
                                      ),
                                      Text(
                                        NubiaMoney.formatCents(
                                            order.purchasePriceCents),
                                      ),
                                    ],
                                  ),
                                ),
                                if (order.status != _kStatusOrder.last)
                                  FilledButton.tonal(
                                    key: Key(
                                        'lab_work_order_advance_${order.id}'),
                                    onPressed: updatingId == order.id
                                        ? null
                                        : () => _advance(order),
                                    child: updatingId == order.id
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : const Text('Avancer'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                    ],
                ],
              );
          }
        },
      ),
    );
  }
}
