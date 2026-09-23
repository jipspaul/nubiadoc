import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/letter_template.dart';
import 'package:nubia_domain/src/entities/letter_template_import_result.dart';

abstract class LetterTemplatesRepository {
  /// `GET /v1/letter-templates` — modèles globaux + ceux du cabinet.
  Future<Either<Failure, List<LetterTemplate>>> list();

  /// `POST /v1/letter-templates/import` (#7157) — importe un modèle `.docx`
  /// propre au cabinet ; renvoie l'id créé et les placeholders détectés.
  Future<Either<Failure, LetterTemplateImportResult>> importDocx({
    required String name,
    required String kind,
    required List<int> bytes,
    required String filename,
  });
}
