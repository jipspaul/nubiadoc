import 'package:dartz/dartz.dart';
import 'package:nubia_data/src/remote/pharmacy_stock/pharmacy_stock_api.dart';
import 'package:nubia_data/src/repositories/pharmacy_failure_mapper.dart';
import 'package:nubia_domain/src/entities/stock_request.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/stock_requests_repository.dart';

class StockRequestsRepositoryImpl implements StockRequestsRepository {
  final PharmacyStockApi _api;

  const StockRequestsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<StockRequest>>> list() => guardPharmacyCall(
        () async => (await _api.list()).map((dto) => dto.toDomain()).toList(),
        errorMessage: 'Impossible de charger les demandes de stock.',
      );

  @override
  Future<Either<Failure, StockRequest>> create({
    required String pharmacyId,
    required List<StockRequestItem> items,
  }) =>
      guardPharmacyCall(
        () async => (await _api.create(pharmacyId: pharmacyId, items: items))
            .toDomain(),
        errorMessage: 'Impossible d’envoyer la demande de stock.',
      );

  @override
  Future<Either<Failure, StockRequest>> accept(String id) => guardPharmacyCall(
        () async => (await _api.accept(id)).toDomain(),
        errorMessage: 'Impossible d’accepter la demande.',
      );

  @override
  Future<Either<Failure, StockRequest>> reject(String id, {String? note}) =>
      guardPharmacyCall(
        () async => (await _api.reject(id, note: note)).toDomain(),
        errorMessage: 'Impossible de refuser la demande.',
      );

  @override
  Future<Either<Failure, StockRequest>> fulfill(String id) => guardPharmacyCall(
        () async => (await _api.fulfill(id)).toDomain(),
        errorMessage: 'Impossible de clore la demande.',
      );

  @override
  Future<Either<Failure, StockRequest>> resend(String id) => guardPharmacyCall(
        () async => (await _api.resend(id)).toDomain(),
        errorMessage: 'Impossible de relancer la pharmacie.',
      );
}
