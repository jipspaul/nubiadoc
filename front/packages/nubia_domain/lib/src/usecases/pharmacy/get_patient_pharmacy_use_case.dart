import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_directory_repository.dart';

/// Pharmacie déclarée d'un patient, vue praticien.
class GetPatientPharmacyUseCase {
  final PharmacyDirectoryRepository _repository;

  const GetPatientPharmacyUseCase(this._repository);

  Future<Either<Failure, Pharmacy?>> call(String patientId) =>
      _repository.getPatientPharmacy(patientId);
}
