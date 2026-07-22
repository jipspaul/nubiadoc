import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/stock_item.dart';
import 'package:nubia_domain/src/repositories/stock_items_repository.dart';

class ListStockItemsUseCase {
  final StockItemsRepository _repository;

  const ListStockItemsUseCase(this._repository);

  Future<Either<Failure, List<StockItem>>> call() => _repository.listItems();
}
