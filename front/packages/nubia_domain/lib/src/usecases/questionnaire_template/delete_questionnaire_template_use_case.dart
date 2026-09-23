import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/questionnaire_template_repository.dart';

class DeleteQuestionnaireTemplateUseCase {
  final QuestionnaireTemplateRepository _repository;

  const DeleteQuestionnaireTemplateUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) => _repository.delete(id);
}
