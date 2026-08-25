import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

/// Relance manuelle d'une demande de stock encore `sent` (côté cabinet).
class ResendStockRequestUseCase {
  final StockRequestsRepository _repository;

  const ResendStockRequestUseCase(this._repository);

  Future<Either<Failure, StockRequest>> call(String id) =>
      _repository.resend(id);
}
