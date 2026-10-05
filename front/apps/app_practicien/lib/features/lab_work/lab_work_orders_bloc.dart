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
    required CreateLabWorkOrderUseCase create,
  })  : _list = list,
        _updateStatus = updateStatus,
        _create = create,
        super(const LabWorkOrdersLoading()) {
    on<LabWorkOrdersLoadRequested>(_onLoad);
    on<LabWorkOrdersStatusChangeRequested>(_onStatusChange);
    on<LabWorkOrdersCreateRequested>(_onCreate);
  }

  final ListLabWorkOrdersUseCase _list;
  final UpdateLabWorkOrderStatusUseCase _updateStatus;
  final CreateLabWorkOrderUseCase _create;

  Future<void> _onLoad(
    LabWorkOrdersLoadRequested event,
    Emitter<LabWorkOrdersState> emit,
  ) async {
    final current = state;
    final loaded = current is LabWorkOrdersLoaded && current.orders.isNotEmpty
        ? current
        : null;
    if (loaded == null) emit(const LabWorkOrdersLoading());
    final result = await _list();
    result.fold(
      // Un rechargement échoué alors que des bons sont déjà affichés reste
      // non bloquant : la liste est conservée, seule une snackbar signale
      // l'erreur (#5067). Le plein écran `NubiaErrorWidget` ne sert qu'au
      // tout premier chargement, en l'absence de données.
      (failure) => safeEmit(loaded != null
          ? LabWorkOrdersLoaded(loaded.orders, errorMessage: failure.message)
          : LabWorkOrdersError(failure.message)),
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
      // Comme pour le chargement (#5067), l'échec d'une action de ligne ne
      // doit pas faire disparaître la liste déjà affichée : on la conserve
      // et on signale l'erreur via `errorMessage` (snackbar), pas de
      // `NubiaErrorWidget` plein écran pour un échec qui ne concerne qu'une
      // seule ligne (#6657).
      (failure) => safeEmit(LabWorkOrdersLoaded(current.orders,
          errorMessage: failure.message)),
      (newStatus) => safeEmit(LabWorkOrdersLoaded([
        for (final order in current.orders)
          if (order.id == event.orderId)
            order.copyWith(status: newStatus)
          else
            order,
      ])),
    );
  }

  Future<void> _onCreate(
    LabWorkOrdersCreateRequested event,
    Emitter<LabWorkOrdersState> emit,
  ) async {
    final result = await _create(
      patientId: event.patientId,
      labName: event.labName,
      purchasePriceCents: event.purchasePriceCents,
      expectedReturnAt: event.expectedReturnAt,
    );
    final current = state;
    await result.fold(
      // Même traitement que l'échec d'un changement de statut (#5067) : la
      // liste déjà affichée est conservée, seule une snackbar signale
      // l'erreur.
      (failure) async => safeEmit(current is LabWorkOrdersLoaded
          ? LabWorkOrdersLoaded(current.orders, errorMessage: failure.message)
          : LabWorkOrdersError(failure.message)),
      // La réponse ne contient que l'id créé — on recharge la liste pour
      // obtenir le bon complet (`patient_display_name`/`sent_at` résolus
      // côté API), même pattern que `createPrescription`.
      (_) => _onLoad(const LabWorkOrdersLoadRequested(), emit),
    );
  }
}
