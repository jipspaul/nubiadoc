import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class PatchMedicalQuestionnaireUseCase {
  final AccountRepository _repository;

  const PatchMedicalQuestionnaireUseCase(this._repository);

  Future<Either<Failure, MedicalQuestionnaire>> call({
    required String cabinetId,
    Map<String, dynamic>? payload,
    bool submit = false,
  }) {
    return _repository.patchMedicalQuestionnaire(
      cabinetId: cabinetId,
      payload: payload,
      submit: submit,
    );
  }
}
