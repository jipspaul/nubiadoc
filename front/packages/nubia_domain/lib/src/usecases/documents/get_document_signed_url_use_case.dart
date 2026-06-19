import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/document_repository.dart';

class GetDocumentSignedUrlUseCase {
  final DocumentRepository _repository;

  const GetDocumentSignedUrlUseCase(this._repository);

  /// Returns a short-lived signed URL for the document with [documentId].
  Future<Either<Failure, String>> call(String documentId) =>
      _repository.getSignedUrl(documentId);
}
