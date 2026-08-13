import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// Lignes de l'ordonnance d'une commande (vue pharmacie) — molécule,
/// posologie, quantité : le PDF (`GetPharmacyOrderPrescriptionUrlUseCase`)
/// reste le recours.
class GetPharmacyOrderPrescriptionUseCase {
  final PharmacyOrdersRepository _repository;

  const GetPharmacyOrderPrescriptionUseCase(this._repository);

  Future<Either<Failure, List<PrescriptionItem>>> call(String orderId) =>
      _repository.getPrescriptionItems(orderId);
}
