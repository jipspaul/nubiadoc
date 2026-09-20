import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_item_location.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class ListItemLocationsUseCase {
  final StockLocationsRepository _repository;

  const ListItemLocationsUseCase(this._repository);

  Future<Either<Failure, List<StockItemLocation>>> call(String itemId) =>
      _repository.listItemLocations(itemId);
}
