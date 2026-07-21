import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/medical_questionnaire.dart';

/// PORT — lecture/validation du questionnaire médical côté cabinet (#4110).
abstract class CabinetMedicalQuestionnaireRepository {
  /// GET /v1/cabinet/patients/:id/medical-questionnaire — `Right(null)` si
  /// aucune soumission visible (aucune, ou encore en brouillon).
  Future<Either<Failure, MedicalQuestionnaire?>> get(String patientId);

  /// POST /v1/cabinet/patients/:id/medical-questionnaire/review — valide et
  /// importe la dernière soumission dans le dossier médical.
  Future<Either<Failure, MedicalQuestionnaire>> review(String patientId);
}
