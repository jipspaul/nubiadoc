import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class CreateStockLocationUseCase {
  final StockLocationsRepository _repository;

  const CreateStockLocationUseCase(this._repository);

  Future<Either<Failure, String>> call(String name) =>
      _repository.createLocation(name);
}
