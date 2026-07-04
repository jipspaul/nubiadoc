import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

class ListStockRequestsUseCase {
  final StockRequestsRepository _repository;

  const ListStockRequestsUseCase(this._repository);

  Future<Either<Failure, List<StockRequest>>> call() => _repository.list();
}
