import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

/// Token opaque du QR de retrait (zéro PII) + code court dictable au
/// comptoir (#6419) — commande prête uniquement.
class GetPickupTokenUseCase {
  final PatientPharmacyRepository _repository;

  const GetPickupTokenUseCase(this._repository);

  Future<Either<Failure, ({String token, String shortCode})>> call(
          String orderId) =>
      _repository.getPickupToken(orderId);
}
