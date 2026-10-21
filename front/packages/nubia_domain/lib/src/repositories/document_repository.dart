import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/document.dart';

/// Une page unique de documents (#8297) : [nextCursor] permet de charger la
/// suivante à la demande plutôt que de paginer le coffre-fort entier avant
/// le premier rendu. [total] (`page.total`) est le volume complet du
/// coffre-fort, indépendamment du nombre de documents déjà chargés.
typedef PagedDocuments = ({
  List<Document> documents,
  String? nextCursor,
  int? total,
});

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

  /// Comptes par catégorie sur le coffre-fort ENTIER, à coût borné (une
  /// requête par catégorie, `limit: 1`) — #8318 : les puces de facette de
  /// l'écran Documents ne doivent pas dépendre des documents déjà chargés
  /// en mémoire (une page, #8297), mais du volume réel par catégorie côté
  /// serveur.
  Future<Either<Failure, Map<DocumentCategory, int>>> categoryCounts({
    String? patientAccount,
  });

  /// Charge une page unique de documents (#8297) : [cursor] (issu d'un
  /// appel précédent) enchaîne sur `page.next_cursor` au lieu de paginer
  /// jusqu'à épuisement avant de rendre la main — l'écran Documents suivait
  /// jusque-là le même chemin que [getAll] sans [limit] (39 requêtes
  /// séquentielles / 5 s de squelettes avant le premier document, cf.
  /// #8297).
  Future<Either<Failure, PagedDocuments>> getPage({
    int limit,
    String? cursor,
    String? patientAccount,
  });

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
