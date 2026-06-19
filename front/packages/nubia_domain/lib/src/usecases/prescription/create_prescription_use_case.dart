import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/prescription.dart';
import 'package:nubia_domain/src/repositories/prescription_repository.dart';

class CreatePrescriptionUseCase {
  final PrescriptionRepository _repository;

  const CreatePrescriptionUseCase(this._repository);

  Future<Either<Failure, Prescription>> call({
    required String patientId,
    required List<PrescriptionItem> items,
  }) =>
      _repository.createPrescription(patientId: patientId, items: items);
}
