import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/generated_letter.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class LettersRepository {
  /// `POST /v1/patients/:id/letters` — rend [templateId] pour ce patient et
  /// l'ajoute à ses documents (`category = 'courrier'`). [overrides] : clé =
  /// placeholder sans accolades (ex. `"correspondant.nom"`), value = texte
  /// libre saisi à l'écran.
  Future<Either<Failure, GeneratedLetter>> generate(
    String patientId, {
    required String templateId,
    Map<String, String> overrides = const {},
  });
}
