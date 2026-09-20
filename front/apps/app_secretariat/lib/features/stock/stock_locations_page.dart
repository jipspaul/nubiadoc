import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'create_stock_location_dialog.dart';
import 'set_location_threshold_dialog.dart';
import 'stock_locations_bloc.dart';
import 'stock_locations_event.dart';
import 'stock_locations_state.dart';
import 'transfer_stock_dialog.dart';

/// Écran « Stock par salle » (#7182/#7183) : un onglet par localisation du
/// cabinet, transfert entre salles, seuil d'alerte par salle. Distinct de
/// [StockInventoryPage] (quantité globale du cabinet, sans détail par
/// salle, #4146).
class StockLocationsPage extends StatefulWidget {
  const StockLocationsPage({super.key});

  @override
  State<StockLocationsPage> createState() => _StockLocationsPageState();
}

class _StockLocationsPageState extends State<StockLocationsPage> {
  @override
  void initState() {
    super.initState();
    context.read<StockLocationsBloc>().add(const StockLocationsLoadRequested());
  }

  Future<void> _onCreateLocation() async {
    final bloc = context.read<StockLocationsBloc>();
    final name = await showCreateStockLocationDialog(context);
    if (name != null) {
      bloc.add(StockLocationsCreateRequested(name));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock par salle'),
        actions: [
          IconButton(
            key: const Key('new_stock_location_button'),
            tooltip: 'Nouvelle salle',
            icon: const Icon(Icons.add_business_outlined),
            onPressed: _onCreateLocation,
          ),
          IconButton(
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
            onPressed: () => context
                .read<StockLocationsBloc>()
                .add(const StockLocationsLoadRequested()),
          ),
        ],
      ),
      body: BlocConsumer<StockLocationsBloc, StockLocationsState>(
        listenWhen: (_, s) => s is StockLocationsError,
        listener: (context, state) {
          if (state is StockLocationsError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(state.message)),
            );
          }
        },
        builder: (context, state) {
          switch (state) {
            case StockLocationsLoading():
              return const Center(child: CircularProgressIndicator());
            case StockLocationsError(:final message):
              return NubiaErrorWidget(
                message: message,
                onRetry: () => context
                    .read<StockLocationsBloc>()
                    .add(const StockLocationsLoadRequested()),
              );
            case StockLocationsLoaded(:final locations):
              if (locations.isEmpty) {
                return const NubiaEmptyState(
                  key: Key('stock_locations_empty'),
                  icon: Icons.meeting_room_outlined,
                  title: 'Aucune localisation de stock',
                );
              }
              return _LocationTabsView(
                key: ValueKey(locations.length),
                state: state,
              );
          }
        },
      ),
    );
  }
}

class _LocationTabsView extends StatefulWidget {
  const _LocationTabsView({super.key, required this.state});

  final StockLocationsLoaded state;

  @override
  State<_LocationTabsView> createState() => _LocationTabsViewState();
}

class _LocationTabsViewState extends State<_LocationTabsView>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: widget.state.locations.length,
    vsync: this,
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _onTransfer(
    BuildContext context,
    StockItem item,
    String fromLocationId,
  ) async {
    final bloc = context.read<StockLocationsBloc>();
    final result = await showTransferStockDialog(
      context,
      itemLabel: item.label,
      locations: widget.state.locations,
      fromLocationId: fromLocationId,
    );
    if (result != null) {
      bloc.add(StockLocationsTransferRequested(
        itemId: item.id,
        fromLocationId: result.fromLocationId,
        toLocationId: result.toLocationId,
        quantity: result.quantity,
      ));
    }
  }

  Future<void> _onThreshold(
    BuildContext context,
    StockItem item,
    StockItemLocation itemLocation,
  ) async {
    final bloc = context.read<StockLocationsBloc>();
    final result = await showSetLocationThresholdDialog(
      context,
      itemLabel: item.label,
      locationName: itemLocation.locationName,
      currentThreshold: itemLocation.threshold,
    );
    if (result != null) {
      bloc.add(StockLocationsThresholdRequested(
        itemId: item.id,
        locationId: itemLocation.locationId,
        threshold: result.threshold,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          key: const Key('stock_locations_tab_bar'),
          controller: _tabController,
          isScrollable: true,
          tabs: [
            for (final location in widget.state.locations) Tab(text: location.name),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              for (final location in widget.state.locations)
                _LocationItemsList(
                  key: Key('stock_location_tab_${location.id}'),
                  location: location,
                  state: widget.state,
                  onTransfer: (item) => _onTransfer(context, item, location.id),
                  onThreshold: (item, itemLocation) =>
                      _onThreshold(context, item, itemLocation),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LocationItemsList extends StatelessWidget {
  const _LocationItemsList({
    super.key,
    required this.location,
    required this.state,
    required this.onTransfer,
    required this.onThreshold,
  });

  final StockLocation location;
  final StockLocationsLoaded state;
  final ValueChanged<StockItem> onTransfer;
  final void Function(StockItem item, StockItemLocation itemLocation)
      onThreshold;

  @override
  Widget build(BuildContext context) {
    if (state.items.isEmpty) {
      return const NubiaEmptyState(
        key: Key('stock_location_items_empty'),
        icon: Icons.warehouse_outlined,
        title: 'Aucun article en inventaire',
      );
    }
    return ListView.builder(
      key: Key('stock_location_items_list_${location.id}'),
      padding: const EdgeInsets.all(16),
      itemCount: state.items.length,
      itemBuilder: (context, index) {
        final item = state.items[index];
        final itemLocation = state.itemLocations[item.id]?.firstWhere(
          (l) => l.locationId == location.id,
          orElse: () => StockItemLocation(
            locationId: location.id,
            locationName: location.name,
            isMain: location.isMain,
            quantity: 0,
          ),
        );
        final isSubmitting = state.submittingItemId == item.id;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: NubiaCard(
            key: Key('stock_location_item_${location.id}_${item.id}'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.label,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          if (itemLocation?.isBelowThreshold ?? false) ...[
                            const SizedBox(width: 8),
                            const StatusPill(
                              key: Key('stock_location_below_threshold'),
                              label: 'Sous le seuil',
                              variant: StatusPillVariant.warning,
                            ),
                          ],
                        ],
                      ),
                      Text(
                        '${item.reference} · ${itemLocation?.quantity ?? 0} ${item.unit}',
                        key: Key('stock_location_item_qty_${location.id}_${item.id}'),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('stock_location_threshold_${location.id}_${item.id}'),
                  tooltip: "Seuil d'alerte",
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: isSubmitting || itemLocation == null
                      ? null
                      : () => onThreshold(item, itemLocation),
                ),
                FilledButton.tonal(
                  key: Key('stock_location_transfer_${location.id}_${item.id}'),
                  onPressed: isSubmitting || state.locations.length < 2
                      ? null
                      : () => onTransfer(item),
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Transférer'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
