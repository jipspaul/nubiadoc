import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

class ListPharmacyOrdersUseCase {
  final PharmacyOrdersRepository _repository;

  const ListPharmacyOrdersUseCase(this._repository);

  Future<Either<Failure, List<PharmacyOrder>>> call({
    PharmacyOrderStatus? status,
  }) =>
      _repository.list(status: status);
}
