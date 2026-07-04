import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

/// Réponse de la pharmacie à une demande de stock.
enum StockRequestResponse { accept, reject, fulfill }

class RespondStockRequestUseCase {
  final StockRequestsRepository _repository;

  const RespondStockRequestUseCase(this._repository);

  Future<Either<Failure, StockRequest>> call(
    String id,
    StockRequestResponse response, {
    String? note,
  }) {
    switch (response) {
      case StockRequestResponse.accept:
        return _repository.accept(id);
      case StockRequestResponse.reject:
        return _repository.reject(id, note: note);
      case StockRequestResponse.fulfill:
        return _repository.fulfill(id);
    }
  }
}
