import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetMedicalQuestionnaireUseCase {
  final AccountRepository _repository;

  const GetMedicalQuestionnaireUseCase(this._repository);

  Future<Either<Failure, MedicalQuestionnaire?>> call({
    required String cabinetId,
  }) {
    return _repository.getMedicalQuestionnaire(cabinetId: cabinetId);
  }
}
