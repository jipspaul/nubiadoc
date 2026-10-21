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
  final GetPharmacyOrderPrescriptionUseCase _prescriptionItems;
  final SetPharmacyOrderItemPreparedUseCase _setLinePrepared;

  OrderDetailBloc({
    required GetPharmacyOrderUseCase get,
    required AcceptPharmacyOrderUseCase accept,
    required MarkPharmacyOrderReadyUseCase ready,
    required RejectPharmacyOrderUseCase reject,
    required GetPharmacyOrderPrescriptionUrlUseCase prescriptionUrl,
    required GetPharmacyOrderPrescriptionUseCase prescriptionItems,
    required SetPharmacyOrderItemPreparedUseCase setLinePrepared,
  })  : _get = get,
        _accept = accept,
        _ready = ready,
        _reject = reject,
        _prescriptionUrl = prescriptionUrl,
        _prescriptionItems = prescriptionItems,
        _setLinePrepared = setLinePrepared,
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
    on<OrderDetailLinePreparedToggled>(_onLinePreparedToggled);
  }

  Future<void> _onLoad(
    OrderDetailLoadRequested event,
    Emitter<OrderDetailState> emit,
  ) async {
    emit(const OrderDetailLoading());
    final result = await _get(event.orderId);
    await result.fold(
      (failure) async => emit(OrderDetailError(failure.message)),
      (order) async {
        emit(OrderDetailLoaded(order));
        // Dégradation douce : un échec de lecture des lignes n'efface pas la
        // commande déjà chargée — le PDF (openDocumentUrl) reste le recours.
        final itemsResult = await _prescriptionItems(order.id);
        itemsResult.fold(
          (failure) {},
          (items) => emit(OrderDetailLoaded(order, items: items)),
        );
      },
    );
  }

  Future<void> _transition(
    Emitter<OrderDetailState> emit,
    Future<Either<Failure, PharmacyOrder>> Function(String id) action,
  ) async {
    final current = state;
    if (current is! OrderDetailLoaded || current.actionInProgress) return;

    emit(OrderDetailLoaded(
      current.order,
      items: current.items,
      actionInProgress: true,
    ));
    final result = await action(current.order.id);
    result.fold(
      // La commande déjà chargée (patient, timeline, actions) reste
      // affichée : l'échec d'une transition ne doit jamais la remplacer par
      // un écran d'erreur plein écran (#7922, miroir de #7868 côté file).
      (failure) => emit(OrderDetailLoaded(
        current.order,
        items: current.items,
        actionError: failure.message,
      )),
      (order) => emit(OrderDetailLoaded(
        order,
        items: current.items,
      )),
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
        emit(OrderDetailLoaded(current.order, items: current.items));
      },
    );
  }

  Future<void> _onLinePreparedToggled(
    OrderDetailLinePreparedToggled event,
    Emitter<OrderDetailState> emit,
  ) async {
    final current = state;
    if (current is! OrderDetailLoaded) return;
    final item = current.items[event.index];
    if (item.id == null) return; // ligne pas encore persistée côté back.

    final result = await _setLinePrepared(
      current.order.id,
      item.id!,
      prepared: !item.prepared,
    );
    result.fold(
      (failure) => emit(OrderDetailLoaded(
        current.order,
        items: current.items,
        actionInProgress: current.actionInProgress,
        actionError: failure.message,
      )),
      (updatedItem) {
        final items = List<PrescriptionItem>.from(current.items);
        items[event.index] = updatedItem;
        emit(OrderDetailLoaded(
          current.order,
          items: items,
          actionInProgress: current.actionInProgress,
        ));
      },
    );
  }
}
