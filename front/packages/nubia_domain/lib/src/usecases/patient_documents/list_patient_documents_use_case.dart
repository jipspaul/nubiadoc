import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_document.dart';
import 'package:nubia_domain/src/repositories/patient_documents_repository.dart';

class ListPatientDocumentsUseCase {
  final PatientDocumentsRepository _repository;

  const ListPatientDocumentsUseCase(this._repository);

  Future<Either<Failure, List<PatientDocument>>> call(
    String patientId, {
    String? category,
  }) =>
      _repository.list(patientId, category: category);
}
