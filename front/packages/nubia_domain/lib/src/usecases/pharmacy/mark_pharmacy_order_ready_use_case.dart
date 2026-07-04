import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// preparing → ready (commande prête à être retirée).
class MarkPharmacyOrderReadyUseCase {
  final PharmacyOrdersRepository _repository;

  const MarkPharmacyOrderReadyUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(String id) =>
      _repository.markReady(id);
}
