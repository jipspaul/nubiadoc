import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/document.dart';
import 'package:nubia_domain/src/repositories/document_repository.dart';

class UploadDocumentUseCase {
  final DocumentRepository _repository;

  const UploadDocumentUseCase(this._repository);

  Future<Either<Failure, Document>> call({
    required String filePath,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
  }) =>
      _repository.upload(
        filePath: filePath,
        filename: filename,
        mimeType: mimeType,
        category: category,
      );
}
