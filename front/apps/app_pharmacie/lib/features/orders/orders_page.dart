import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'orders_bloc.dart';
import 'orders_event.dart';
import 'orders_state.dart';
import 'widgets/order_row.dart';
import 'widgets/orders_aside.dart';
import 'widgets/orders_kpis.dart';

/// Corps de l'écran « Commandes » — file (tableau) + colonne latérale
/// « À traiter », consommable dans le bodyBuilder du ProShell. L'aside se
/// replie sous [_asideBreakpoint] de largeur disponible.
class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  static const _asideBreakpoint = 900.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _asideBreakpoint) {
          return const OrdersView();
        }
        return const Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: OrdersView()),
            SizedBox(width: 320, child: OrdersAside()),
          ],
        );
      },
    );
  }
}

/// File des commandes entrantes — tableau de la file, consommable seul
/// (utilisé aussi par [OrdersScreen] sur petite largeur).
class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  Completer<void>? _refreshCompleter;
  Timer? _freshnessTicker;

  static const _filters = <(String, PharmacyOrderStatus?)>[
    ('Toutes', null),
    ('Reçues', PharmacyOrderStatus.received),
    ('En préparation', PharmacyOrderStatus.preparing),
    ('Prêtes', PharmacyOrderStatus.ready),
  ];

  @override
  void initState() {
    super.initState();
    // Fait vivre le texte relatif de l'indicateur de fraîcheur (« il y a
    // N s ») sans attendre de nouvelle donnée réseau.
    _freshnessTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _freshnessTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrdersBloc, OrdersState>(
      listener: (context, state) {
        if (state is OrdersLoaded || state is OrdersError) {
          _refreshCompleter?.complete();
          _refreshCompleter = null;
        }
      },
      builder: (context, state) {
        final currentFilter = switch (state) {
          OrdersLoaded(:final filter) => filter,
          _ => null,
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (state is OrdersLoaded) OrdersKpiBanner(orders: state.orders),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final (label, value) in _filters)
                          NubiaChip(
                            key: Key('orders_filter_${value?.name ?? 'all'}'),
                            label: label,
                            selected: value == currentFilter,
                            onTap: () => context
                                .read<OrdersBloc>()
                                .add(OrdersFilterChanged(value)),
                          ),
                      ],
                    ),
                  ),
                  if (state is OrdersLoaded) ...[
                    const SizedBox(width: 8),
                    _FreshnessIndicator(updatedAt: state.updatedAt),
                  ],
                ],
              ),
            ),
            Expanded(child: _buildBody(context, state)),
          ],
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, OrdersState state) {
    switch (state) {
      case OrdersLoading():
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              NubiaSkeletonLoader(height: 64),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 64),
              SizedBox(height: 8),
              NubiaSkeletonLoader(height: 64),
            ],
          ),
        );
      case OrdersError(:final message):
        return NubiaErrorWidget(
          message: message,
          onRetry: () =>
              context.read<OrdersBloc>().add(const OrdersRefreshRequested()),
        );
      case OrdersLoaded(:final pendingOrderId):
        final orders = state.visible;
        if (orders.isEmpty) {
          return const NubiaEmptyState(
            icon: Icons.shopping_bag_outlined,
            title: 'Aucune commande',
            subtitle: 'Les ordonnances transmises par les patients '
                'apparaîtront ici.',
          );
        }
        return RefreshIndicator(
          onRefresh: () {
            _refreshCompleter = Completer<void>();
            context.read<OrdersBloc>().add(const OrdersRefreshRequested());
            return _refreshCompleter!.future;
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return OrderRow(
                order: order,
                onTap: () => context.go('/orders/${order.id}'),
                actionInProgress: pendingOrderId == order.id,
              );
            },
          ),
        );
    }
  }
}

/// Pastille verte + texte relatif — âge de la dernière donnée reçue.
class _FreshnessIndicator extends StatelessWidget {
  const _FreshnessIndicator({required this.updatedAt});

  final DateTime updatedAt;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: NubiaColors.brand600,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'Mise à jour il y a ${_relativeAge(updatedAt)}',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: NubiaColors.n500),
        ),
      ],
    );
  }
}

String _relativeAge(DateTime updatedAt) {
  final elapsed = DateTime.now().difference(updatedAt);
  if (elapsed.inSeconds < 60) return '${elapsed.inSeconds} s';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min';
  return '${elapsed.inHours} h';
}
