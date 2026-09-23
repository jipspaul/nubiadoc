import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/questionnaire_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetActiveMedicalQuestionnaireTemplateUseCase {
  final AccountRepository _repository;

  const GetActiveMedicalQuestionnaireTemplateUseCase(this._repository);

  Future<Either<Failure, QuestionnaireTemplate>> call({
    required String cabinetId,
  }) {
    return _repository.getActiveMedicalQuestionnaireTemplate(
      cabinetId: cabinetId,
    );
  }
}
