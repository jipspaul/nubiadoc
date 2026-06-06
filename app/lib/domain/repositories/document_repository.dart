import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/document.dart';

abstract class DocumentRepository {
  Future<Either<Failure, List<Document>>> getAll();
  Future<Either<Failure, List<Document>>> getByCategory(DocumentCategory category);
  /// Returns a short-lived signed URL for download/display.
  Future<Either<Failure, String>> getSignedUrl(String documentId);
  /// Uploads a file as a multipart/form-data POST to /v1/documents.
  Future<Either<Failure, Document>> upload({
    required String filePath,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
  });
}
