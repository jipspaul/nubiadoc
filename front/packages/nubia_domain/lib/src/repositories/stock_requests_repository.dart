import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';

/// Demandes de stock cabinet → pharmacie.
///
/// Le même port sert les deux bords ; le DI de chaque app n'enregistre que
/// l'implémentation de son espace (`/v1/pharmacy/*` ou `/v1/cabinet/*`).
abstract class StockRequestsRepository {
  /// GET /v1/pharmacy/stock-requests ou /v1/cabinet/stock-requests.
  Future<Either<Failure, List<StockRequest>>> list();

  /// POST /v1/cabinet/stock-requests (émission côté cabinet).
  Future<Either<Failure, StockRequest>> create({
    required String pharmacyId,
    required List<StockRequestItem> items,
  });

  /// POST /v1/pharmacy/stock-requests/{id}/accept
  Future<Either<Failure, StockRequest>> accept(String id, {String? note});

  /// POST /v1/pharmacy/stock-requests/{id}/reject
  Future<Either<Failure, StockRequest>> reject(String id, {String? note});

  /// POST /v1/pharmacy/stock-requests/{id}/fulfill
  Future<Either<Failure, StockRequest>> fulfill(String id);

  /// POST /v1/cabinet/stock-requests/{id}/resend (relance manuelle, cabinet).
  Future<Either<Failure, StockRequest>> resend(String id);
}
