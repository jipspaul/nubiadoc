import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'add_stock_movement_dialog.dart';
import 'stock_inventory_bloc.dart';
import 'stock_inventory_event.dart';
import 'stock_inventory_state.dart';

/// Écran « Inventaire » côté cabinet (#4146) : articles de stock réels
/// (`GET /v1/cabinet/stock-items`), badge sous le seuil d'alerte, formulaire
/// de réception/ajustement. Distinct de [StockPage] (demandes de
/// réapprovisionnement vers une pharmacie, lot B5, #3507).
class StockInventoryPage extends StatefulWidget {
  const StockInventoryPage({super.key});

  @override
  State<StockInventoryPage> createState() => _StockInventoryPageState();
}

class _StockInventoryPageState extends State<StockInventoryPage> {
  @override
  void initState() {
    super.initState();
    context.read<StockInventoryBloc>().add(const StockInventoryLoadRequested());
  }

  Future<void> _onMovement(String itemId, String itemLabel) async {
    final bloc = context.read<StockInventoryBloc>();
    final result =
        await showAddStockMovementDialog(context, itemLabel: itemLabel);
    if (result != null) {
      bloc.add(StockInventoryMovementRequested(
        itemId: itemId,
        delta: result.delta,
        reason: result.reason,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventaire'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<StockInventoryBloc>()
                .add(const StockInventoryLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<StockInventoryBloc, StockInventoryState>(
        listenWhen: (_, s) => s is StockInventoryError,
        listener: (context, state) {
          if (state is StockInventoryError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          switch (state) {
            case StockInventoryLoading():
              return const Center(child: CircularProgressIndicator());
            case StockInventoryError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<StockInventoryBloc>()
                    .add(const StockInventoryLoadRequested()),
              );
            case StockInventoryLoaded(:final items, :final submittingItemId):
              if (items.isEmpty) {
                return const NubiaEmptyState(
                  key: Key('stock_inventory_empty'),
                  icon: Icons.warehouse_outlined,
                  title: 'Aucun article en inventaire',
                );
              }
              return ListView.builder(
                key: const Key('stock_inventory_list'),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NubiaCard(
                      key: Key('stock_item_${item.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(item.label,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    if (item.isBelowAlertThreshold) ...[
                                      const SizedBox(width: 8),
                                      const StatusPill(
                                        key: Key('stock_item_below_threshold'),
                                        label: 'Sous le seuil',
                                        variant: StatusPillVariant.warning,
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  '${item.reference} · '
                                  '${item.quantityOnHand} ${item.unit}',
                                  key: Key('stock_item_qty_${item.id}'),
                                ),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            key: Key('stock_item_movement_${item.id}'),
                            onPressed: submittingItemId == item.id
                                ? null
                                : () => _onMovement(item.id, item.label),
                            child: submittingItemId == item.id
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Text('Mouvement'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
