import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'lab_work_order_metrics.dart';
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

/// Libellé du bouton d'avancement selon le statut courant (#5061, point 4 de
/// la maquette) : annonce l'effet de la transition plutôt qu'un « Avancer »
/// générique, sans changer l'événement émis par [_advance].
const _kStatusTransitionLabels = <String, String>{
  'sent': "Passer à l'essayage",
  'try_in': 'Marquer retourné',
  'returned': 'Programmer la pose',
};

/// `sentAt` (ISO 8601) → `dd/MM/yyyy`, même convention que
/// `patient_fiche.dart` (pas de dépendance `intl` dans ce package).
String _formatSentAt(String iso) {
  final d = DateTime.parse(iso);
  return '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/'
      '${d.year}';
}

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

  /// Action de relance labo (#5062, point 5 de la maquette) : sur un bon en
  /// retard, relancer le labo est la bonne réponse — pas avancer le statut.
  /// Aucun endpoint de relance n'existe côté API : feedback local en
  /// attendant l'intégration, on ne touche pas au statut du bon.
  void _relaunchLab(LabWorkOrder order) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Labo relancé')),
    );
  }

  /// Bon actif (non `fitted`) dont la date de retour attendue est dépassée —
  /// même prédicat que [computeLabWorkOrderMetrics] (#5063).
  bool _isOverdue(LabWorkOrder order, DateTime now) {
    if (order.status == _kStatusOrder.last) return false;
    final expectedReturnAt = order.expectedReturnAt;
    if (expectedReturnAt == null) return false;
    return DateTime.parse(expectedReturnAt).isBefore(now);
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
        listenWhen: (_, s) =>
            s is LabWorkOrdersLoaded && s.errorMessage != null,
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
                        child:
                            NubiaSkeletonLoader(height: 88, borderRadius: 12),
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
              final now = DateTime.now();
              return ListView(
                key: const Key('lab_work_orders_list'),
                padding: const EdgeInsets.all(16),
                children: [
                  _LabWorkOrdersMetricsBand(orders: orders),
                  const SizedBox(height: 16),
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
                            child: _isOverdue(order, now)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      _LabWorkOrderInfo(order: order),
                                      const SizedBox(height: 12),
                                      NubiaButton(
                                        key: Key(
                                            'lab_work_order_relaunch_${order.id}'),
                                        label: 'Relancer le labo',
                                        icon: Icons.call,
                                        isLoading: updatingId == order.id,
                                        onPressed: updatingId == order.id
                                            ? null
                                            : () => _relaunchLab(order),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                          child: _LabWorkOrderInfo(
                                              order: order)),
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
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2),
                                                )
                                              : Text(_kStatusTransitionLabels[order.status] ??
                                  'Avancer'),
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

/// Bande de 4 [MetricTile] dérivés des bons (#5063, point 7 de la maquette) :
/// aucun total, aucun filtre — juste de quoi répondre aux questions du matin.
class _LabWorkOrdersMetricsBand extends StatelessWidget {
  const _LabWorkOrdersMetricsBand({required this.orders});

  final List<LabWorkOrder> orders;

  @override
  Widget build(BuildContext context) {
    final metrics = computeLabWorkOrderMetrics(orders, now: DateTime.now());

    return Row(
      key: const Key('lab_work_metrics_band'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_in_progress'),
            icon: Icons.hourglass_top_outlined,
            value: '${metrics.inProgressCount}',
            label: 'bons en cours',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_overdue'),
            icon: Icons.error_outline,
            value: '${metrics.overdueCount}',
            label: 'en retard',
            variant: MetricTileVariant.danger,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_due_this_week'),
            icon: Icons.event_outlined,
            value: '${metrics.dueThisWeekCount}',
            label: 'attendus cette semaine',
            variant: MetricTileVariant.warning,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: MetricTile(
            key: const Key('lab_work_metric_committed'),
            icon: Icons.payments_outlined,
            value: NubiaMoney.formatCents(metrics.committedCents),
            label: 'engagé chez les labos',
          ),
        ),
      ],
    );
  }
}

/// Bloc labo + statut + pied de carte (date d'envoi, prix), commun aux deux
/// rendus de carte (bon en retard ou non, #5062).
class _LabWorkOrderInfo extends StatelessWidget {
  const _LabWorkOrderInfo({required this.order});

  final LabWorkOrder order;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                order.labName,
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            StatusPill(
              key: Key('lab_work_order_status_${order.id}'),
              label: _kStatusLabels[order.status] ?? order.status,
              variant: _kStatusVariants[order.status] ?? StatusPillVariant.info,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          key: Key('lab_work_order_footer_${order.id}'),
          children: [
            Expanded(
              child: Text(
                'Envoyé le ${_formatSentAt(order.sentAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            Text(
              NubiaMoney.formatCents(order.purchasePriceCents),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFeatures: tabularFigures,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}
