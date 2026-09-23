import 'package:equatable/equatable.dart';

sealed class DashboardLayoutState extends Equatable {
  const DashboardLayoutState();

  @override
  List<Object?> get props => [];
}

final class DashboardLayoutLoading extends DashboardLayoutState {
  const DashboardLayoutLoading();
}

final class DashboardLayoutLoaded extends DashboardLayoutState {
  /// Ordre d'affichage de TOUT le catalogue (widgets visibles ET masqués) —
  /// permet de proposer un ordre stable en mode édition même pour les
  /// widgets actuellement masqués.
  final List<String> order;

  /// Sous-ensemble de [order] actuellement masqué. Le complémentaire, dans
  /// l'ordre de [order], est exactement la liste persistée côté API.
  final Set<String> hiddenIds;

  final bool editing;

  const DashboardLayoutLoaded({
    required this.order,
    required this.hiddenIds,
    this.editing = false,
  });

  List<String> get visibleOrder =>
      order.where((id) => !hiddenIds.contains(id)).toList();

  DashboardLayoutLoaded copyWith({
    List<String>? order,
    Set<String>? hiddenIds,
    bool? editing,
  }) =>
      DashboardLayoutLoaded(
        order: order ?? this.order,
        hiddenIds: hiddenIds ?? this.hiddenIds,
        editing: editing ?? this.editing,
      );

  @override
  List<Object?> get props => [order, hiddenIds, editing];
}

final class DashboardLayoutError extends DashboardLayoutState {
  final String message;

  const DashboardLayoutError(this.message);

  @override
  List<Object?> get props => [message];
}
