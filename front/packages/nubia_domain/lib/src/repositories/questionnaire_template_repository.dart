import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/questionnaire_question.dart';
import 'package:nubia_domain/src/entities/questionnaire_template.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class QuestionnaireTemplateRepository {
  /// `GET /v1/cabinet/questionnaire-templates` — catalogue global + modèle
  /// du cabinet s'il existe (un seul modèle actif par cabinet, contrairement
  /// à `ConsentTemplateRepository`).
  Future<Either<Failure, List<QuestionnaireTemplate>>> list();

  /// `POST /v1/cabinet/questionnaire-templates` — crée le modèle propre au
  /// cabinet. `ServerFailure(statusCode: 409)` si le cabinet en a déjà un.
  Future<Either<Failure, ({String id, int version})>> create({
    required String title,
    required List<QuestionnaireQuestion> schema,
  });

  /// `PATCH /v1/cabinet/questionnaire-templates/:id` — fait évoluer le
  /// modèle du cabinet. N'édite jamais la ligne existante : le serveur
  /// désactive la version courante et insère une nouvelle ligne — `id`
  /// retourné est celui de cette NOUVELLE ligne, distinct de celui passé en
  /// paramètre.
  Future<Either<Failure, ({String id, int version})>> patch(
    String id, {
    String? title,
    List<QuestionnaireQuestion>? schema,
  });

  /// `DELETE /v1/cabinet/questionnaire-templates/:id` — désactive le modèle
  /// du cabinet (jamais de suppression physique).
  Future<Either<Failure, void>> delete(String id);
}
