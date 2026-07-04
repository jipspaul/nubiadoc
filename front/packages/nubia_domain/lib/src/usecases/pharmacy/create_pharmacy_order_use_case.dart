import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_order.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

/// Transmet une ordonnance à une pharmacie (crée la commande, vue patient).
class CreatePharmacyOrderUseCase {
  final PatientPharmacyRepository _repository;

  const CreatePharmacyOrderUseCase(this._repository);

  Future<Either<Failure, PharmacyOrder>> call({
    required String prescriptionId,
    required String pharmacyId,
  }) =>
      _repository.createOrder(
        prescriptionId: prescriptionId,
        pharmacyId: pharmacyId,
      );
}
