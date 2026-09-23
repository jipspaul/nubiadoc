import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/letter_template_import_result.dart';
import 'package:nubia_domain/src/repositories/letter_templates_repository.dart';

class ImportLetterTemplateUseCase {
  final LetterTemplatesRepository _repository;

  const ImportLetterTemplateUseCase(this._repository);

  Future<Either<Failure, LetterTemplateImportResult>> call({
    required String name,
    required String kind,
    required List<int> bytes,
    required String filename,
  }) =>
      _repository.importDocx(
        name: name,
        kind: kind,
        bytes: bytes,
        filename: filename,
      );
}
