import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'orders_event.dart';
import 'orders_state.dart';

/// File des commandes click-and-collect (vue pharmacie).
///
/// Chargement REST initial puis rafraîchissement via le
/// [PharmacyOrderEventsPort] (polling aujourd'hui, WebSocket au lot F10 —
/// le bloc ne voit que le port).
class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final ListPharmacyOrdersUseCase _list;
  final WatchPharmacyOrdersUseCase _watch;
  StreamSubscription<List<PharmacyOrder>>? _subscription;

  OrdersBloc({
    required ListPharmacyOrdersUseCase list,
    required WatchPharmacyOrdersUseCase watch,
  })  : _list = list,
        _watch = watch,
        super(const OrdersLoading()) {
    on<OrdersSubscribed>(_onSubscribed);
    on<OrdersRefreshRequested>(_onRefreshRequested);
    on<OrdersFilterChanged>(_onFilterChanged);
    on<OrdersStreamUpdated>(_onStreamUpdated);
  }

  Future<void> _onSubscribed(
    OrdersSubscribed event,
    Emitter<OrdersState> emit,
  ) async {
    await _load(emit);
    await _subscription?.cancel();
    _subscription = _watch().listen(
      (orders) => add(OrdersStreamUpdated(orders)),
      onError:
          (_) {}, // les erreurs de poll sont silencieuses (retry au tick suivant)
    );
  }

  Future<void> _onRefreshRequested(
    OrdersRefreshRequested event,
    Emitter<OrdersState> emit,
  ) =>
      _load(emit);

  Future<void> _load(Emitter<OrdersState> emit) async {
    final filter = switch (state) {
      OrdersLoaded(:final filter) => filter,
      _ => null,
    };
    try {
      final result = await _list();
      result.fold(
        (failure) => emit(OrdersError(failure.message)),
        (orders) => emit(OrdersLoaded(orders: orders, filter: filter)),
      );
    } catch (_) {
      emit(const OrdersError('Impossible de charger les commandes.'));
    }
  }

  void _onFilterChanged(OrdersFilterChanged event, Emitter<OrdersState> emit) {
    final current = state;
    if (current is OrdersLoaded) {
      emit(OrdersLoaded(orders: current.orders, filter: event.filter));
    }
  }

  void _onStreamUpdated(OrdersStreamUpdated event, Emitter<OrdersState> emit) {
    final filter = switch (state) {
      OrdersLoaded(:final filter) => filter,
      _ => null,
    };
    emit(OrdersLoaded(orders: event.orders, filter: filter));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
