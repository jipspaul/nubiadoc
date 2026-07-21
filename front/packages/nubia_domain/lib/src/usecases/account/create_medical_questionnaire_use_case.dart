import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class CreateMedicalQuestionnaireUseCase {
  final AccountRepository _repository;

  const CreateMedicalQuestionnaireUseCase(this._repository);

  Future<Either<Failure, MedicalQuestionnaire>> call({
    required String cabinetId,
    required Map<String, dynamic> payload,
  }) {
    return _repository.createMedicalQuestionnaire(
      cabinetId: cabinetId,
      payload: payload,
    );
  }
}
