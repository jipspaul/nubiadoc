import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_tag.dart';
import 'package:nubia_domain/src/repositories/patient_tags_repository.dart';

class CreatePatientTagUseCase {
  final PatientTagsRepository _repository;

  const CreatePatientTagUseCase(this._repository);

  Future<Either<Failure, PatientTag>> call(
    String patientId, {
    required String label,
    String? color,
  }) =>
      _repository.create(patientId, label: label, color: color);
}
