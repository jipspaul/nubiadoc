import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class SetItemLocationThresholdUseCase {
  final StockLocationsRepository _repository;

  const SetItemLocationThresholdUseCase(this._repository);

  Future<Either<Failure, void>> call(
    String itemId,
    String locationId, {
    int? threshold,
  }) =>
      _repository.setItemLocationThreshold(
        itemId,
        locationId,
        threshold: threshold,
      );
}
