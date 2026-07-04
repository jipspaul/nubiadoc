import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class GetMyPharmacyUseCase {
  final PatientPharmacyRepository _repository;

  const GetMyPharmacyUseCase(this._repository);

  Future<Either<Failure, Pharmacy?>> call() => _repository.getMyPharmacy();
}
