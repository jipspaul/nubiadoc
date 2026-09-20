import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_location.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class ListStockLocationsUseCase {
  final StockLocationsRepository _repository;

  const ListStockLocationsUseCase(this._repository);

  Future<Either<Failure, List<StockLocation>>> call() =>
      _repository.listLocations();
}
