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
  /// the whole vault. [onPage] (ignored when [category] or [limit] is set)
  /// is called with each page as it arrives, ahead of the final result.
  Future<Either<Failure, List<Document>>> call({
    DocumentCategory? category,
    int? limit,
    void Function(List<Document> page)? onPage,
  }) {
    if (category != null) {
      return _repository.getByCategory(category);
    }
    return _repository.getAll(limit: limit, onPage: onPage);
  }
}
