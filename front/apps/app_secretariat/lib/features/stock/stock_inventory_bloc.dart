import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_inventory_event.dart';
import 'stock_inventory_state.dart';

/// Inventaire réel du cabinet (#4146) : liste des `stock_item` +
/// réception/ajustement (`GET`/`POST /v1/cabinet/stock-items`,
/// `POST .../movements`). Distinct de [StockBloc] (demandes de
/// réapprovisionnement vers une pharmacie, lot B5, #3507).
class StockInventoryBloc extends Bloc<StockInventoryEvent, StockInventoryState>
    with SafeEmitMixin<StockInventoryState> {
  StockInventoryBloc({
    required ListStockItemsUseCase list,
    required AddStockMovementUseCase addMovement,
  })  : _list = list,
        _addMovement = addMovement,
        super(const StockInventoryLoading()) {
    on<StockInventoryLoadRequested>(_onLoad);
    on<StockInventoryMovementRequested>(_onMovement);
  }

  final ListStockItemsUseCase _list;
  final AddStockMovementUseCase _addMovement;

  Future<void> _onLoad(
    StockInventoryLoadRequested event,
    Emitter<StockInventoryState> emit,
  ) async {
    emit(const StockInventoryLoading());
    final result = await _list();
    result.fold(
      (failure) => safeEmit(StockInventoryError(failure.message)),
      (items) => safeEmit(StockInventoryLoaded(items)),
    );
  }

  Future<void> _onMovement(
    StockInventoryMovementRequested event,
    Emitter<StockInventoryState> emit,
  ) async {
    final current = state;
    if (current is! StockInventoryLoaded || current.submittingItemId != null) {
      return;
    }

    emit(StockInventoryLoaded(current.items, submittingItemId: event.itemId));
    final result = await _addMovement(
      event.itemId,
      delta: event.delta,
      reason: event.reason,
    );
    result.fold(
      (failure) => safeEmit(StockInventoryError(failure.message)),
      (quantityOnHand) => safeEmit(StockInventoryLoaded([
        for (final item in current.items)
          if (item.id == event.itemId)
            item.copyWith(quantityOnHand: quantityOnHand)
          else
            item,
      ])),
    );
  }
}
