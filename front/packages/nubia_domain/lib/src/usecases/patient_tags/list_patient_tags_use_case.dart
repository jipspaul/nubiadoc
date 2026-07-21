import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_tag.dart';
import 'package:nubia_domain/src/repositories/patient_tags_repository.dart';

class ListPatientTagsUseCase {
  final PatientTagsRepository _repository;

  const ListPatientTagsUseCase(this._repository);

  Future<Either<Failure, List<PatientTag>>> call(String patientId) =>
      _repository.list(patientId);
}
