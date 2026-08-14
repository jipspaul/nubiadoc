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
  final AcceptPharmacyOrderUseCase _accept;
  final MarkPharmacyOrderReadyUseCase _ready;
  StreamSubscription<List<PharmacyOrder>>? _subscription;
  Timer? _refreshTimer;

  /// Rafraîchissement périodique auto (poste fixe au comptoir, sans geste
  /// tactile) — ordre de grandeur cohérent avec l'indicateur de fraîcheur de
  /// la maquette (« il y a 12 s »). S'ajoute au pull-to-refresh, ne le
  /// remplace pas.
  static const _autoRefreshInterval = Duration(seconds: 15);

  OrdersBloc({
    required ListPharmacyOrdersUseCase list,
    required WatchPharmacyOrdersUseCase watch,
    required AcceptPharmacyOrderUseCase accept,
    required MarkPharmacyOrderReadyUseCase ready,
  })  : _list = list,
        _watch = watch,
        _accept = accept,
        _ready = ready,
        super(const OrdersLoading()) {
    on<OrdersSubscribed>(_onSubscribed);
    on<OrdersRefreshRequested>(_onRefreshRequested);
    on<OrdersFilterChanged>(_onFilterChanged);
    on<OrdersStreamUpdated>(_onStreamUpdated);
    on<OrdersAutoRefreshTicked>(_onAutoRefreshTicked);
    on<OrdersTransitionRequested>(_onTransitionRequested);
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
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      _autoRefreshInterval,
      (_) => add(const OrdersAutoRefreshTicked()),
    );
  }

  Future<void> _onRefreshRequested(
    OrdersRefreshRequested event,
    Emitter<OrdersState> emit,
  ) =>
      _load(emit);

  Future<void> _onAutoRefreshTicked(
    OrdersAutoRefreshTicked event,
    Emitter<OrdersState> emit,
  ) =>
      _load(emit, silent: true);

  Future<void> _load(Emitter<OrdersState> emit, {bool silent = false}) async {
    final filter = switch (state) {
      OrdersLoaded(:final filter) => filter,
      _ => null,
    };
    try {
      final result = await _list();
      result.fold(
        (failure) {
          if (!silent) emit(OrdersError(failure.message));
        },
        (orders) => emit(OrdersLoaded(orders: orders, filter: filter)),
      );
    } catch (_) {
      if (!silent) {
        emit(const OrdersError('Impossible de charger les commandes.'));
      }
    }
  }

  void _onFilterChanged(OrdersFilterChanged event, Emitter<OrdersState> emit) {
    final current = state;
    if (current is OrdersLoaded) {
      emit(OrdersLoaded(
        orders: current.orders,
        filter: event.filter,
        updatedAt: current.updatedAt,
      ));
    }
  }

  void _onStreamUpdated(OrdersStreamUpdated event, Emitter<OrdersState> emit) {
    final filter = switch (state) {
      OrdersLoaded(:final filter) => filter,
      _ => null,
    };
    emit(OrdersLoaded(orders: event.orders, filter: filter));
  }

  Future<void> _onTransitionRequested(
    OrdersTransitionRequested event,
    Emitter<OrdersState> emit,
  ) async {
    final current = state;
    if (current is! OrdersLoaded || current.pendingOrderId != null) return;
    if (event.target != PharmacyOrderStatus.preparing &&
        event.target != PharmacyOrderStatus.ready) {
      return;
    }

    emit(OrdersLoaded(
      orders: current.orders,
      filter: current.filter,
      pendingOrderId: event.orderId,
      updatedAt: current.updatedAt,
    ));
    final result = event.target == PharmacyOrderStatus.preparing
        ? await _accept(event.orderId)
        : await _ready(event.orderId);
    result.fold(
      (failure) => emit(OrdersError(failure.message)),
      (updated) => emit(OrdersLoaded(
        orders: [
          for (final order in current.orders)
            if (order.id == updated.id) updated else order,
        ],
        filter: current.filter,
      )),
    );
  }

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
