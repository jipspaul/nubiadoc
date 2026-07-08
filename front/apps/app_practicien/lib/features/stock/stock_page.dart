import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'create_stock_request_dialog.dart';
import 'stock_bloc.dart';
import 'stock_event.dart';
import 'stock_state.dart';

/// Écran « Stock » côté cabinet (lot B5, #3507) : demandes de stock envoyées
/// aux pharmacies partenaires (`POST /v1/cabinet/stock-requests`) et suivi de
/// leur statut (`sent` → `accepted`/`rejected` → `fulfilled`, ou `cancelled`).
class StockPage extends StatefulWidget {
  const StockPage({super.key});

  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  static const _labels = {
    StockRequestStatus.sent: 'Envoyée',
    StockRequestStatus.accepted: 'Acceptée',
    StockRequestStatus.rejected: 'Refusée',
    StockRequestStatus.fulfilled: 'Honorée',
    StockRequestStatus.cancelled: 'Annulée',
  };

  static const _variants = {
    StockRequestStatus.sent: StatusPillVariant.info,
    StockRequestStatus.accepted: StatusPillVariant.warning,
    StockRequestStatus.rejected: StatusPillVariant.error,
    StockRequestStatus.fulfilled: StatusPillVariant.success,
    StockRequestStatus.cancelled: StatusPillVariant.error,
  };

  @override
  void initState() {
    super.initState();
    context.read<StockBloc>().add(const StockLoadRequested());
  }

  Future<void> _onCreate() async {
    final bloc = context.read<StockBloc>();
    final result = await showCreateStockRequestDialog(context);
    if (result != null) {
      bloc.add(StockCreateRequested(
        pharmacyId: result.pharmacyId,
        items: result.items,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () =>
                context.read<StockBloc>().add(const StockLoadRequested()),
          ),
        ],
      ),
      body: BlocBuilder<StockBloc, StockState>(
        builder: (context, state) {
          switch (state) {
            case StockLoading():
              return const Center(child: CircularProgressIndicator());
            case StockError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<StockBloc>()
                    .add(const StockLoadRequested()),
              );
            case StockLoaded(:final requests):
              if (requests.isEmpty) {
                return const NubiaEmptyState(
                  icon: Icons.inventory_2_outlined,
                  title: 'Aucune demande de stock',
                  subtitle:
                      'Envoyez une demande à une pharmacie partenaire.',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NubiaCard(
                      key: Key('stock_request_${request.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              StatusPill(
                                label: _labels[request.status]!,
                                variant: _variants[request.status]!,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          for (final item in request.items)
                            Text(
                              '• ${item.quantity} × ${item.label}'
                              '${item.note != null ? ' (${item.note})' : ''}',
                            ),
                          if (request.responseNote != null) ...[
                            const SizedBox(height: 4),
                            Text('Note pharmacie : ${request.responseNote}'),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
          }
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new_stock_request_fab'),
        onPressed: _onCreate,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle demande'),
      ),
    );
  }
}
