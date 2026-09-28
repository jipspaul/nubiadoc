import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/document.dart';

abstract class DocumentRepository {
  /// [onPage], si fourni, est appelé avec chaque page dès sa réception —
  /// permet de peindre la 1re page pendant que les suivantes se chargent
  /// en tâche de fond plutôt que d'attendre le drainage complet (#7913).
  Future<Either<Failure, List<Document>>> getAll({
    int? limit,
    void Function(List<Document> page)? onPage,
  });
  Future<Either<Failure, List<Document>>> getByCategory(
      DocumentCategory category);

  /// Returns a short-lived signed URL for download/display.
  Future<Either<Failure, String>> getSignedUrl(String documentId);

  /// Uploads a file as a multipart/form-data POST to /v1/documents.
  Future<Either<Failure, Document>> upload({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
  });
}
