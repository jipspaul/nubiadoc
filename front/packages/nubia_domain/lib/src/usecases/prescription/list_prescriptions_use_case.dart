import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class ListPrescriptionsUseCase {
  final PrescriptionRepository _repository;

  const ListPrescriptionsUseCase(this._repository);

  Future<Either<Failure, List<Prescription>>> call(String patientId) =>
      _repository.listPrescriptions(patientId);
}
