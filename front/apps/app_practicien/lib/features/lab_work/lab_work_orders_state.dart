import 'package:nubia_domain/nubia_domain.dart';

sealed class LabWorkOrdersState {
  const LabWorkOrdersState();
}

class LabWorkOrdersLoading extends LabWorkOrdersState {
  const LabWorkOrdersLoading();

  @override
  bool operator ==(Object other) => other is LabWorkOrdersLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class LabWorkOrdersLoaded extends LabWorkOrdersState {
  const LabWorkOrdersLoaded(this.orders, {this.updatingId});

  final List<LabWorkOrder> orders;

  /// Id du bon dont le changement de statut est en cours (bouton en
  /// loading), `null` si aucune mise à jour en cours.
  final String? updatingId;

  @override
  bool operator ==(Object other) =>
      other is LabWorkOrdersLoaded &&
      other.updatingId == updatingId &&
      other.orders.length == orders.length &&
      List.generate(
        orders.length,
        (i) => other.orders[i] == orders[i],
      ).every((b) => b);

  @override
  int get hashCode => Object.hash(Object.hashAll(orders), updatingId);
}

class LabWorkOrdersError extends LabWorkOrdersState {
  const LabWorkOrdersError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is LabWorkOrdersError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
