import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_items_repository.dart';

class AddStockMovementUseCase {
  final StockItemsRepository _repository;

  const AddStockMovementUseCase(this._repository);

  Future<Either<Failure, int>> call(
    String itemId, {
    required int delta,
    required String reason,
    String? expiryDate,
    String? consultationActId,
  }) =>
      _repository.addMovement(
        itemId,
        delta: delta,
        reason: reason,
        expiryDate: expiryDate,
        consultationActId: consultationActId,
      );
}
