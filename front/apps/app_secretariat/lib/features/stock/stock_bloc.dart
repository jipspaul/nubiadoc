import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'stock_event.dart';
import 'stock_state.dart';

/// Demandes de stock émises par le cabinet vers une pharmacie partenaire
/// (lot B5, #3507) : création + suivi (`GET`/`POST /v1/cabinet/stock-requests`).
class StockBloc extends Bloc<StockEvent, StockState>
    with SafeEmitMixin<StockState> {
  StockBloc({
    required ListStockRequestsUseCase list,
    required CreateStockRequestUseCase create,
    required ResendStockRequestUseCase resend,
  })  : _list = list,
        _create = create,
        _resend = resend,
        super(const StockLoading()) {
    on<StockLoadRequested>(_onLoad);
    on<StockCreateRequested>(_onCreate);
    on<StockResendRequested>(_onResend);
  }

  final ListStockRequestsUseCase _list;
  final CreateStockRequestUseCase _create;
  final ResendStockRequestUseCase _resend;

  Future<void> _onLoad(
      StockLoadRequested event, Emitter<StockState> emit) async {
    emit(const StockLoading());
    final result = await _list();
    result.fold(
      (failure) => safeEmit(StockError(failure.message)),
      (requests) => safeEmit(StockLoaded(requests)),
    );
  }

  Future<void> _onCreate(
    StockCreateRequested event,
    Emitter<StockState> emit,
  ) async {
    final current = state;
    if (current is! StockLoaded || current.creating) return;

    emit(StockLoaded(current.requests, creating: true));
    final result = await _create(
      pharmacyId: event.pharmacyId,
      items: event.items,
    );
    result.fold(
      (failure) => safeEmit(StockError(failure.message)),
      (created) =>
          safeEmit(StockLoaded([created, ...current.requests])),
    );
  }

  Future<void> _onResend(
    StockResendRequested event,
    Emitter<StockState> emit,
  ) async {
    final current = state;
    if (current is! StockLoaded || current.resendingId != null) return;

    emit(StockLoaded(current.requests, resendingId: event.requestId));
    final result = await _resend(event.requestId);
    result.fold(
      (failure) => safeEmit(StockError(failure.message)),
      (updated) => safeEmit(StockLoaded([
        for (final request in current.requests)
          if (request.id == updated.id) updated else request,
      ])),
    );
  }
}
