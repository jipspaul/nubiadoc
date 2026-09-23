import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/questionnaire_template_repository.dart';

class CreateQuestionnaireTemplateUseCase {
  final QuestionnaireTemplateRepository _repository;

  const CreateQuestionnaireTemplateUseCase(this._repository);

  Future<Either<Failure, ({String id, int version})>> call({
    required String title,
    required List<QuestionnaireQuestion> schema,
  }) =>
      _repository.create(title: title, schema: schema);
}
