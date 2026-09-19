import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/consent_template.dart';
import 'package:nubia_domain/src/entities/rendered_consent_template.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class ConsentTemplateRepository {
  /// `GET /v1/cabinet/consent-templates` — catalogue global + modèles du
  /// cabinet.
  Future<Either<Failure, List<ConsentTemplate>>> list();

  /// `POST /v1/cabinet/consent-templates` — crée un modèle propre au cabinet.
  Future<Either<Failure, ({String id, int version})>> create({
    required String actCategory,
    required String title,
    required String bodyMarkdown,
  });

  /// `PATCH /v1/cabinet/consent-templates/:id` — fait évoluer un modèle du
  /// cabinet. N'édite jamais la ligne existante : le serveur désactive la
  /// version courante et insère une nouvelle ligne — `id` retourné est celui
  /// de cette NOUVELLE ligne, distinct de celui passé en paramètre.
  Future<Either<Failure, ({String id, int version})>> patch(
    String id, {
    String? actCategory,
    String? title,
    String? bodyMarkdown,
  });

  /// `POST /v1/consent-templates/:id/render` — rend le modèle pour un
  /// patient et un devis donnés, stocké comme document patient.
  Future<Either<Failure, RenderedConsentTemplate>> render(
    String id, {
    required String quoteId,
  });
}
