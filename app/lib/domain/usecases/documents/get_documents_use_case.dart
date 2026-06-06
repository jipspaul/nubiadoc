import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';

@injectable
class GetDocumentsUseCase {
  final DocumentRepository _repository;

  const GetDocumentsUseCase(this._repository);

  /// Returns all documents when [category] is null, or only those matching
  /// the given [category].
  Future<Either<Failure, List<Document>>> call({
    DocumentCategory? category,
  }) {
    if (category != null) {
      return _repository.getByCategory(category);
    }
    return _repository.getAll();
  }
}
