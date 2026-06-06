import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';

@injectable
class GetDocumentSignedUrlUseCase {
  final DocumentRepository _repository;

  const GetDocumentSignedUrlUseCase(this._repository);

  /// Returns a short-lived signed URL for the document with [documentId].
  Future<Either<Failure, String>> call(String documentId) =>
      _repository.getSignedUrl(documentId);
}
