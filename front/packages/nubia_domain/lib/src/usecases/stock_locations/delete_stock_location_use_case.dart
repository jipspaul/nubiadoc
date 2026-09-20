import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class DeleteStockLocationUseCase {
  final StockLocationsRepository _repository;

  const DeleteStockLocationUseCase(this._repository);

  Future<Either<Failure, void>> call(String locationId) =>
      _repository.deleteLocation(locationId);
}
