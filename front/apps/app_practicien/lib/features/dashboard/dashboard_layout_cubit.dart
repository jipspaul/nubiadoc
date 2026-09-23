import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'dashboard_layout_state.dart';
import 'dashboard_widget_catalog.dart';

export 'dashboard_layout_state.dart';

/// Registre de widgets + mode édition + persistance du dashboard praticien
/// (#7161) — `GET/PUT /v1/me/dashboard-layout`. Masquer/réordonner un widget
/// persiste immédiatement (pas de bouton « Enregistrer » séparé), avec
/// rollback silencieux vers l'état précédent en cas d'échec réseau — même
/// esprit optimiste que `NotificationPrefsCubit.save`.
class DashboardLayoutCubit extends Cubit<DashboardLayoutState>
    with SafeEmitMixin<DashboardLayoutState> {
  DashboardLayoutCubit({
    required GetDashboardLayoutUseCase get,
    required UpdateDashboardLayoutUseCase update,
    this.catalog = kProDashboardWidgetCatalog,
  })  : _get = get,
        _update = update,
        super(const DashboardLayoutLoading());

  final GetDashboardLayoutUseCase _get;
  final UpdateDashboardLayoutUseCase _update;
  final List<String> catalog;

  Future<void> load() async {
    emit(const DashboardLayoutLoading());
    final result = await _get();
    result.fold(
      (failure) => safeEmit(DashboardLayoutError(failure.message)),
      (visible) => safeEmit(_loadedFrom(visible)),
    );
  }

  DashboardLayoutLoaded _loadedFrom(List<String> visible, {bool editing = false}) {
    final hidden = catalog.where((id) => !visible.contains(id));
    return DashboardLayoutLoaded(
      order: [...visible, ...hidden],
      hiddenIds: hidden.toSet(),
      editing: editing,
    );
  }

  void toggleEditing() {
    final current = state;
    if (current is! DashboardLayoutLoaded) return;
    safeEmit(current.copyWith(editing: !current.editing));
  }

  /// Bascule la visibilité d'un widget du catalogue — masqué s'il était
  /// visible, réinsérée en fin de liste visible sinon.
  Future<void> toggleVisibility(String widgetId) async {
    final current = state;
    if (current is! DashboardLayoutLoaded) return;
    final hidden = Set<String>.from(current.hiddenIds);
    if (!hidden.remove(widgetId)) {
      hidden.add(widgetId);
    }
    await _persist(current, current.order, hidden);
  }

  /// Réordonne le widget de [oldIndex] vers [newIndex] dans [order]. Suit la
  /// convention `ReorderableListView.onReorder` : [newIndex] est calculé
  /// AVANT le retrait de l'élément déplacé.
  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = state;
    if (current is! DashboardLayoutLoaded) return;
    final order = List<String>.from(current.order);
    final targetIndex = oldIndex < newIndex ? newIndex - 1 : newIndex;
    final widgetId = order.removeAt(oldIndex);
    order.insert(targetIndex, widgetId);
    await _persist(current, order, current.hiddenIds);
  }

  Future<void> _persist(
    DashboardLayoutLoaded previous,
    List<String> order,
    Set<String> hiddenIds,
  ) async {
    safeEmit(
      DashboardLayoutLoaded(
        order: order,
        hiddenIds: hiddenIds,
        editing: previous.editing,
      ),
    );
    final visible = order.where((id) => !hiddenIds.contains(id)).toList();
    final result = await _update(visible);
    result.fold(
      (failure) => safeEmit(previous),
      (saved) => safeEmit(_loadedFrom(saved, editing: previous.editing)),
    );
  }
}
