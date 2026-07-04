import 'package:bloc/bloc.dart';
import 'package:dartz/dartz.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'order_detail_event.dart';
import 'order_detail_state.dart';

/// Détail d'une commande + transitions (le serveur reste l'autorité :
/// transition illégale → 409 remonté en message d'erreur).
class OrderDetailBloc extends Bloc<OrderDetailEvent, OrderDetailState> {
  final GetPharmacyOrderUseCase _get;
  final AcceptPharmacyOrderUseCase _accept;
  final MarkPharmacyOrderReadyUseCase _ready;
  final RejectPharmacyOrderUseCase _reject;
  final GetPharmacyOrderPrescriptionUrlUseCase _prescriptionUrl;

  OrderDetailBloc({
    required GetPharmacyOrderUseCase get,
    required AcceptPharmacyOrderUseCase accept,
    required MarkPharmacyOrderReadyUseCase ready,
    required RejectPharmacyOrderUseCase reject,
    required GetPharmacyOrderPrescriptionUrlUseCase prescriptionUrl,
  })  : _get = get,
        _accept = accept,
        _ready = ready,
        _reject = reject,
        _prescriptionUrl = prescriptionUrl,
        super(const OrderDetailLoading()) {
    on<OrderDetailLoadRequested>(_onLoad);
    on<OrderDetailAcceptRequested>(
      (event, emit) => _transition(emit, (id) => _accept(id)),
    );
    on<OrderDetailReadyRequested>(
      (event, emit) => _transition(emit, (id) => _ready(id)),
    );
    on<OrderDetailRejectRequested>(
      (event, emit) => _transition(emit, (id) => _reject(id, event.reason)),
    );
    on<OrderDetailDocumentRequested>(_onDocumentRequested);
  }

  Future<void> _onLoad(
    OrderDetailLoadRequested event,
    Emitter<OrderDetailState> emit,
  ) async {
    emit(const OrderDetailLoading());
    final result = await _get(event.orderId);
    result.fold(
      (failure) => emit(OrderDetailError(failure.message)),
      (order) => emit(OrderDetailLoaded(order)),
    );
  }

  Future<void> _transition(
    Emitter<OrderDetailState> emit,
    Future<Either<Failure, PharmacyOrder>> Function(String id) action,
  ) async {
    final current = state;
    if (current is! OrderDetailLoaded || current.actionInProgress) return;

    emit(OrderDetailLoaded(current.order, actionInProgress: true));
    final result = await action(current.order.id);
    result.fold(
      (failure) => emit(OrderDetailError(failure.message)),
      (order) => emit(OrderDetailLoaded(order)),
    );
  }

  Future<void> _onDocumentRequested(
    OrderDetailDocumentRequested event,
    Emitter<OrderDetailState> emit,
  ) async {
    final current = state;
    if (current is! OrderDetailLoaded) return;

    final result = await _prescriptionUrl(current.order.id);
    result.fold(
      (failure) => emit(OrderDetailError(failure.message)),
      (url) {
        emit(OrderDetailDocumentReady(current.order, url));
        emit(OrderDetailLoaded(current.order));
      },
    );
  }
}
