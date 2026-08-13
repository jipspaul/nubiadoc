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

/// File des commandes entrantes — corps de l'écran « Commandes »,
/// consommable dans le bodyBuilder du ProShell.
class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  Completer<void>? _refreshCompleter;

  static const _filters = <(String, PharmacyOrderStatus?)>[
    ('Toutes', null),
    ('Reçues', PharmacyOrderStatus.received),
    ('En préparation', PharmacyOrderStatus.preparing),
    ('Prêtes', PharmacyOrderStatus.ready),
  ];

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
            Padding(
              padding: const EdgeInsets.all(16),
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
