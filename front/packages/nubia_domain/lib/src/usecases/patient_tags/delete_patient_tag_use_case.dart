import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_tags_repository.dart';

class DeletePatientTagUseCase {
  final PatientTagsRepository _repository;

  const DeletePatientTagUseCase(this._repository);

  Future<Either<Failure, void>> call(String patientId, String tagId) =>
      _repository.delete(patientId, tagId);
}
