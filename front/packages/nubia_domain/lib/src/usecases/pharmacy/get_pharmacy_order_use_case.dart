import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

class GetPharmacyOrderUseCase {
  final PharmacyOrdersRepository _repository;

  const GetPharmacyOrderUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(String id) =>
      _repository.getById(id);
}
