import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/document.dart';
import 'package:nubia_domain/src/repositories/document_repository.dart';

class GetDocumentsUseCase {
  final DocumentRepository _repository;

  const GetDocumentsUseCase(this._repository);

  /// Returns all documents when [category] is null, or only those matching
  /// the given [category]. [limit] bounds the number of documents returned
  /// to a single page (ignored when [category] is set) — omit it to fetch
  /// the whole vault.
  ///
  /// [patientAccount] (#8262) : identifiant du proche dont on consulte le
  /// coffre-fort — `null` renvoie celui du titulaire.
  Future<Either<Failure, List<Document>>> call({
    DocumentCategory? category,
    int? limit,
    String? patientAccount,
  }) {
    if (category != null) {
      return _repository.getByCategory(category);
    }
    return _repository.getAll(limit: limit, patientAccount: patientAccount);
  }

  /// Nombre total de documents, à coût borné (une page) — #8279.
  Future<Either<Failure, int>> count({String? patientAccount}) =>
      _repository.count(patientAccount: patientAccount);

  /// Comptes par catégorie sur le coffre-fort entier (#8318) — voir
  /// [DocumentRepository.categoryCounts].
  Future<Either<Failure, Map<DocumentCategory, int>>> categoryCounts({
    String? patientAccount,
  }) =>
      _repository.categoryCounts(patientAccount: patientAccount);

  /// Charge une page unique de documents (#8297) — voir [DocumentRepository.getPage].
  Future<Either<Failure, PagedDocuments>> getPage({
    int limit = 20,
    String? cursor,
    String? patientAccount,
  }) =>
      _repository.getPage(
        limit: limit,
        cursor: cursor,
        patientAccount: patientAccount,
      );
}
