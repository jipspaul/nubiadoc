import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/consent_template_repository.dart';

class PatchConsentTemplateUseCase {
  final ConsentTemplateRepository _repository;

  const PatchConsentTemplateUseCase(this._repository);

  Future<Either<Failure, ({String id, int version})>> call(
    String id, {
    String? actCategory,
    String? title,
    String? bodyMarkdown,
  }) =>
      _repository.patch(
        id,
        actCategory: actCategory,
        title: title,
        bodyMarkdown: bodyMarkdown,
      );
}
