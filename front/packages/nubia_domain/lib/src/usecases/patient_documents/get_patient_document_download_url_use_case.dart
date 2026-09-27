import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_documents_repository.dart';

class GetPatientDocumentDownloadUrlUseCase {
  final PatientDocumentsRepository _repository;

  const GetPatientDocumentDownloadUrlUseCase(this._repository);

  /// Returns a short-lived signed URL for [documentId] in [patientId]'s
  /// cabinet-side vault (#6952).
  Future<Either<Failure, String>> call(String patientId, String documentId) =>
      _repository.getDownloadUrl(patientId, documentId);
}
