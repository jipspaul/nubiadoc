import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/patient_documents_repository.dart';

class UploadPatientDocumentUseCase {
  final PatientDocumentsRepository _repository;

  const UploadPatientDocumentUseCase(this._repository);

  Future<Either<Failure, String>> call(
    String patientId, {
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required String category,
  }) =>
      _repository.upload(
        patientId,
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
        category: category,
      );
}
