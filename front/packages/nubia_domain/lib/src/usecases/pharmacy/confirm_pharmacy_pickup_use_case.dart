import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// ready → pickedUp via le token du QR patient (scan ou saisie manuelle).
class ConfirmPharmacyPickupUseCase {
  final PharmacyOrdersRepository _repository;

  const ConfirmPharmacyPickupUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call(
    String token, {
    required String expectedOrderId,
  }) =>
      _repository.confirmPickup(token, expectedOrderId: expectedOrderId);
}
