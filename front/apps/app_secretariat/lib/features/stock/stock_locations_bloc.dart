import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_locations_event.dart';
import 'stock_locations_state.dart';

/// Stock par salle du cabinet (#7182/#7183) : localisations
/// (`GET/POST /v1/cabinet/stock-locations`), quantité/seuil de chaque
/// article par localisation (`GET /v1/cabinet/stock-items/:id/locations`),
/// transfert entre salles (`POST .../transfer`) et réglage du seuil d'alerte
/// par salle (`PATCH .../locations/:locationId`).
class StockLocationsBloc extends Bloc<StockLocationsEvent, StockLocationsState>
    with SafeEmitMixin<StockLocationsState> {
  StockLocationsBloc({
    required ListStockLocationsUseCase listLocations,
    required ListStockItemsUseCase listItems,
    required ListItemLocationsUseCase listItemLocations,
    required CreateStockLocationUseCase createLocation,
    required TransferStockUseCase transfer,
    required SetItemLocationThresholdUseCase setThreshold,
  })  : _listLocations = listLocations,
        _listItems = listItems,
        _listItemLocations = listItemLocations,
        _createLocation = createLocation,
        _transfer = transfer,
        _setThreshold = setThreshold,
        super(const StockLocationsLoading()) {
    on<StockLocationsLoadRequested>(_onLoad);
    on<StockLocationsCreateRequested>(_onCreate);
    on<StockLocationsTransferRequested>(_onTransfer);
    on<StockLocationsThresholdRequested>(_onThreshold);
  }

  final ListStockLocationsUseCase _listLocations;
  final ListStockItemsUseCase _listItems;
  final ListItemLocationsUseCase _listItemLocations;
  final CreateStockLocationUseCase _createLocation;
  final TransferStockUseCase _transfer;
  final SetItemLocationThresholdUseCase _setThreshold;

  Future<void> _onLoad(
    StockLocationsLoadRequested event,
    Emitter<StockLocationsState> emit,
  ) async {
    emit(const StockLocationsLoading());

    final locationsResult = await _listLocations();
    final locations = locationsResult.fold((failure) => null, (v) => v);
    if (locations == null) {
      safeEmit(StockLocationsError(
        locationsResult.fold((f) => f.message, (_) => ''),
      ));
      return;
    }

    final itemsResult = await _listItems();
    final items = itemsResult.fold((failure) => null, (v) => v);
    if (items == null) {
      safeEmit(StockLocationsError(
        itemsResult.fold((f) => f.message, (_) => ''),
      ));
      return;
    }

    final itemLocationsResults =
        await Future.wait(items.map((item) => _listItemLocations(item.id)));
    final itemLocations = <String, List<StockItemLocation>>{};
    for (var i = 0; i < items.length; i++) {
      itemLocationsResults[i]
          .fold((failure) {}, (locs) => itemLocations[items[i].id] = locs);
    }

    safeEmit(StockLocationsLoaded(
      locations: locations,
      items: items,
      itemLocations: itemLocations,
    ));
  }

  Future<void> _onCreate(
    StockLocationsCreateRequested event,
    Emitter<StockLocationsState> emit,
  ) async {
    final result = await _createLocation(event.name);
    final failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      safeEmit(StockLocationsError(failure.message));
      return;
    }
    await _onLoad(const StockLocationsLoadRequested(), emit);
  }

  Future<void> _onTransfer(
    StockLocationsTransferRequested event,
    Emitter<StockLocationsState> emit,
  ) async {
    final current = state;
    if (current is! StockLocationsLoaded || current.submittingItemId != null) {
      return;
    }

    emit(StockLocationsLoaded(
      locations: current.locations,
      items: current.items,
      itemLocations: current.itemLocations,
      submittingItemId: event.itemId,
    ));

    final result = await _transfer(
      event.itemId,
      fromLocationId: event.fromLocationId,
      toLocationId: event.toLocationId,
      quantity: event.quantity,
    );

    result.fold(
      (failure) => safeEmit(StockLocationsError(failure.message)),
      (quantities) {
        final locs = List<StockItemLocation>.from(
          current.itemLocations[event.itemId] ?? const [],
        );
        final fromIndex =
            locs.indexWhere((l) => l.locationId == event.fromLocationId);
        if (fromIndex != -1) {
          locs[fromIndex] =
              locs[fromIndex].copyWithQuantity(quantities.$1);
        }
        final toIndex =
            locs.indexWhere((l) => l.locationId == event.toLocationId);
        if (toIndex != -1) {
          locs[toIndex] = locs[toIndex].copyWithQuantity(quantities.$2);
        }

        safeEmit(StockLocationsLoaded(
          locations: current.locations,
          items: current.items,
          itemLocations: {
            ...current.itemLocations,
            event.itemId: locs,
          },
        ));
      },
    );
  }

  Future<void> _onThreshold(
    StockLocationsThresholdRequested event,
    Emitter<StockLocationsState> emit,
  ) async {
    final current = state;
    if (current is! StockLocationsLoaded || current.submittingItemId != null) {
      return;
    }

    emit(StockLocationsLoaded(
      locations: current.locations,
      items: current.items,
      itemLocations: current.itemLocations,
      submittingItemId: event.itemId,
    ));

    final result = await _setThreshold(
      event.itemId,
      event.locationId,
      threshold: event.threshold,
    );

    result.fold(
      (failure) => safeEmit(StockLocationsError(failure.message)),
      (_) {
        final locs = List<StockItemLocation>.from(
          current.itemLocations[event.itemId] ?? const [],
        );
        final index =
            locs.indexWhere((l) => l.locationId == event.locationId);
        if (index != -1) {
          locs[index] = locs[index].copyWithThreshold(event.threshold);
        }

        safeEmit(StockLocationsLoaded(
          locations: current.locations,
          items: current.items,
          itemLocations: {
            ...current.itemLocations,
            event.itemId: locs,
          },
        ));
      },
    );
  }
}
