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
  const LabWorkOrdersLoaded(this.orders, {this.updatingId, this.errorMessage});

  final List<LabWorkOrder> orders;

  /// Id du bon dont le changement de statut est en cours (bouton en
  /// loading), `null` si aucune mise à jour en cours.
  final String? updatingId;

  /// Erreur transitoire d'un rechargement échoué alors que des bons sont
  /// déjà affichés : signale la snackbar sans effacer la liste (#5067).
  final String? errorMessage;

  @override
  bool operator ==(Object other) =>
      other is LabWorkOrdersLoaded &&
      other.updatingId == updatingId &&
      other.errorMessage == errorMessage &&
      other.orders.length == orders.length &&
      List.generate(
        orders.length,
        (i) => other.orders[i] == orders[i],
      ).every((b) => b);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(orders), updatingId, errorMessage);
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
