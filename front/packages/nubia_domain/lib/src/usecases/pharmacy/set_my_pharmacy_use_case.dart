import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class SetMyPharmacyUseCase {
  final PatientPharmacyRepository _repository;

  const SetMyPharmacyUseCase(this._repository);

  Future<Either<Failure, Pharmacy>> call(String pharmacyId) =>
      _repository.setMyPharmacy(pharmacyId);
}
