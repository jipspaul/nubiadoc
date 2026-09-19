import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/consent_template_repository.dart';

class CreateConsentTemplateUseCase {
  final ConsentTemplateRepository _repository;

  const CreateConsentTemplateUseCase(this._repository);

  Future<Either<Failure, ({String id, int version})>> call({
    required String actCategory,
    required String title,
    required String bodyMarkdown,
  }) =>
      _repository.create(
        actCategory: actCategory,
        title: title,
        bodyMarkdown: bodyMarkdown,
      );
}
