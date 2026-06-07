import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/prescription.dart';
import 'package:nubia_patient/domain/repositories/prescription_repository.dart';

@injectable
class CreatePrescriptionUseCase {
  final PrescriptionRepository _repository;

  const CreatePrescriptionUseCase(this._repository);

  Future<Either<Failure, Prescription>> call({
    required String patientId,
    required List<PrescriptionItem> items,
  }) =>
      _repository.createPrescription(patientId: patientId, items: items);
}
