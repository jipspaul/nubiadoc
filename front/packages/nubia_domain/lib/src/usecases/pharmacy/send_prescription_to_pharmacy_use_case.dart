import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

/// Envoi d'une ordonnance signée à une pharmacie (côté praticien).
class SendPrescriptionToPharmacyUseCase {
  final PrescriptionRepository _repository;

  const SendPrescriptionToPharmacyUseCase(this._repository);

  Future<Either<Failure, Prescription>> call({
    required String prescriptionId,
    required String pharmacyId,
  }) =>
      _repository.sendToPharmacy(
        prescriptionId: prescriptionId,
        pharmacyId: pharmacyId,
      );
}
