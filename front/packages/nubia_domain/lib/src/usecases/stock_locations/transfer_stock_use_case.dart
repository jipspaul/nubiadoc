import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class TransferStockUseCase {
  final StockLocationsRepository _repository;

  const TransferStockUseCase(this._repository);

  Future<Either<Failure, (int fromQuantity, int toQuantity)>> call(
    String itemId, {
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
  }) =>
      _repository.transfer(
        itemId,
        fromLocationId: fromLocationId,
        toLocationId: toLocationId,
        quantity: quantity,
      );
}
