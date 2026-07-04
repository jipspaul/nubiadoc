import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

/// Émission d'une demande de stock (côté cabinet).
class CreateStockRequestUseCase {
  final StockRequestsRepository _repository;

  const CreateStockRequestUseCase(this._repository);

  Future<Either<Failure, StockRequest>> call({
    required String pharmacyId,
    required List<StockRequestItem> items,
  }) =>
      _repository.create(pharmacyId: pharmacyId, items: items);
}
