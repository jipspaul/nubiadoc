import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'lab_work_orders_event.dart';
import 'lab_work_orders_state.dart';

/// Suivi des bons de travaux prothétiques (#4149) : liste + changement de
/// statut (`GET`/`PATCH /v1/cabinet/lab-work-orders`).
class LabWorkOrdersBloc extends Bloc<LabWorkOrdersEvent, LabWorkOrdersState>
    with SafeEmitMixin<LabWorkOrdersState> {
  LabWorkOrdersBloc({
    required ListLabWorkOrdersUseCase list,
    required UpdateLabWorkOrderStatusUseCase updateStatus,
  })  : _list = list,
        _updateStatus = updateStatus,
        super(const LabWorkOrdersLoading()) {
    on<LabWorkOrdersLoadRequested>(_onLoad);
    on<LabWorkOrdersStatusChangeRequested>(_onStatusChange);
  }

  final ListLabWorkOrdersUseCase _list;
  final UpdateLabWorkOrderStatusUseCase _updateStatus;

  Future<void> _onLoad(
    LabWorkOrdersLoadRequested event,
    Emitter<LabWorkOrdersState> emit,
  ) async {
    emit(const LabWorkOrdersLoading());
    final result = await _list();
    result.fold(
      (failure) => safeEmit(LabWorkOrdersError(failure.message)),
      (orders) => safeEmit(LabWorkOrdersLoaded(orders)),
    );
  }

  Future<void> _onStatusChange(
    LabWorkOrdersStatusChangeRequested event,
    Emitter<LabWorkOrdersState> emit,
  ) async {
    final current = state;
    if (current is! LabWorkOrdersLoaded || current.updatingId != null) return;

    emit(LabWorkOrdersLoaded(current.orders, updatingId: event.orderId));
    final result = await _updateStatus(event.orderId, event.status);
    result.fold(
      (failure) => safeEmit(LabWorkOrdersError(failure.message)),
      (newStatus) => safeEmit(LabWorkOrdersLoaded([
        for (final order in current.orders)
          if (order.id == event.orderId)
            order.copyWith(status: newStatus)
          else
            order,
      ])),
    );
  }
}
