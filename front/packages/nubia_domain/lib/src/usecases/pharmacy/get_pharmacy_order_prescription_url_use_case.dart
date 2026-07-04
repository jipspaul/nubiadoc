import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// URL signée du PDF d'ordonnance d'une commande (vue pharmacie).
class GetPharmacyOrderPrescriptionUrlUseCase {
  final PharmacyOrdersRepository _repository;

  const GetPharmacyOrderPrescriptionUrlUseCase(this._repository);

  Future<Either<Failure, String>> call(String orderId) =>
      _repository.getPrescriptionUrl(orderId);
}
