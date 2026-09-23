import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/questionnaire_template_repository.dart';

class PatchQuestionnaireTemplateUseCase {
  final QuestionnaireTemplateRepository _repository;

  const PatchQuestionnaireTemplateUseCase(this._repository);

  Future<Either<Failure, ({String id, int version})>> call(
    String id, {
    String? title,
    List<QuestionnaireQuestion>? schema,
  }) =>
      _repository.patch(id, title: title, schema: schema);
}
