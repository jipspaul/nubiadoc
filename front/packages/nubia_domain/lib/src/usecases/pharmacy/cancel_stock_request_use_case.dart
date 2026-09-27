import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

/// Annulation d'une demande de stock encore `sent` (côté cabinet, #7818).
class CancelStockRequestUseCase {
  final StockRequestsRepository _repository;

  const CancelStockRequestUseCase(this._repository);

  Future<Either<Failure, StockRequest>> call(String id) =>
      _repository.cancel(id);
}
