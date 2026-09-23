import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/questionnaire_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/questionnaire_template_repository.dart';

class ListQuestionnaireTemplatesUseCase {
  final QuestionnaireTemplateRepository _repository;

  const ListQuestionnaireTemplatesUseCase(this._repository);

  Future<Either<Failure, List<QuestionnaireTemplate>>> call() =>
      _repository.list();
}
