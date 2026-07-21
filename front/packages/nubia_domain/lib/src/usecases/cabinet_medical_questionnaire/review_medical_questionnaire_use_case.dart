import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';
import 'package:nubia_domain/src/repositories/cabinet_medical_questionnaire_repository.dart';

class ReviewMedicalQuestionnaireUseCase {
  final CabinetMedicalQuestionnaireRepository _repository;

  const ReviewMedicalQuestionnaireUseCase(this._repository);

  Future<Either<Failure, MedicalQuestionnaire>> call(String patientId) =>
      _repository.review(patientId);
}
