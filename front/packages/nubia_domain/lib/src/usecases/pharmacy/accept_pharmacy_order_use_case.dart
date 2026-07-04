import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// received → preparing (le pharmacien démarre la préparation).
class AcceptPharmacyOrderUseCase {
  final PharmacyOrdersRepository _repository;

  const AcceptPharmacyOrderUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(String id) =>
      _repository.accept(id);
}
