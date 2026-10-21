import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/document.dart';

abstract class DocumentRepository {
  /// [patientAccount] (#8262) : `?patient_account=` côté API — résolu
  /// tuteur→proche côté serveur (`api/src/documents.rs`).
  Future<Either<Failure, List<Document>>> getAll({
    int? limit,
    String? patientAccount,
  });
  Future<Either<Failure, List<Document>>> getByCategory(
      DocumentCategory category);

  /// Nombre total de documents, à coût borné (une page) — #8279.
  Future<Either<Failure, int>> count({String? patientAccount});

  /// Returns a short-lived signed URL for download/display.
  Future<Either<Failure, String>> getSignedUrl(String documentId);

  /// Uploads a file as a multipart/form-data POST to /v1/documents.
  ///
  /// [patientAccount] (#8274) : symétrique de `getAll` — dépose le document
  /// chez ce proche plutôt que chez le titulaire.
  Future<Either<Failure, Document>> upload({
    required List<int> bytes,
    required String filename,
    required String mimeType,
    required DocumentCategory category,
    String? patientAccount,
  });
}
