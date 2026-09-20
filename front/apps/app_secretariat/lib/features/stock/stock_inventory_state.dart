import 'package:nubia_domain/nubia_domain.dart';

sealed class StockInventoryState {
  const StockInventoryState();
}

class StockInventoryLoading extends StockInventoryState {
  const StockInventoryLoading();

  @override
  bool operator ==(Object other) => other is StockInventoryLoading;

  @override
  int get hashCode => runtimeType.hashCode;
}

class StockInventoryLoaded extends StockInventoryState {
  const StockInventoryLoaded(this.items, {this.submittingItemId});

  final List<StockItem> items;

  /// Id de l'article dont le mouvement est en cours de soumission (bouton en
  /// loading), `null` si aucune soumission en cours.
  final String? submittingItemId;

  @override
  bool operator ==(Object other) =>
      other is StockInventoryLoaded &&
      other.submittingItemId == submittingItemId &&
      other.items.length == items.length &&
      List.generate(
        items.length,
        (i) => other.items[i] == items[i],
      ).every((b) => b);

  @override
  int get hashCode => Object.hash(Object.hashAll(items), submittingItemId);
}

class StockInventoryError extends StockInventoryState {
  const StockInventoryError(this.message);

  final String message;

  @override
  bool operator ==(Object other) =>
      other is StockInventoryError && other.message == message;

  @override
  int get hashCode => message.hashCode;
}
