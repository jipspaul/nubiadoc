import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// received → rejected (motif obligatoire).
class RejectPharmacyOrderUseCase {
  final PharmacyOrdersRepository _repository;

  const RejectPharmacyOrderUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(String id, String reason) =>
      _repository.reject(id, reason);
}
