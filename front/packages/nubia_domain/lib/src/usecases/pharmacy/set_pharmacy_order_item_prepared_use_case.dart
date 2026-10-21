import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_orders_repository.dart';

/// Coche/décoche une ligne d'ordonnance « sortie des rayons » (#6783,
/// maquette `Pharmacie Delivrance v2.html` point 7). Réservé à `preparing`
/// côté serveur — 409 remonté sinon, le serveur reste l'autorité.
class SetPharmacyOrderItemPreparedUseCase {
  final PharmacyOrdersRepository _repository;

  const SetPharmacyOrderItemPreparedUseCase(this._repository);

  Future<Either<Failure, PrescriptionItem>> call(
    String orderId,
    String itemId, {
    required bool prepared,
  }) =>
      _repository.setPrescriptionItemPrepared(
        orderId,
        itemId,
        prepared: prepared,
      );
}
