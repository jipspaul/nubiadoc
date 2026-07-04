import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_prescription.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_pharmacy_repository.dart';

class ListMyPrescriptionsUseCase {
  final PatientPharmacyRepository _repository;

  const ListMyPrescriptionsUseCase(this._repository);

  Future<Either<Failure, List<PatientPrescription>>> call() =>
      _repository.listPrescriptions();
}
