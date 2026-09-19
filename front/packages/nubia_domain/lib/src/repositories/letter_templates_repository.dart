import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/letter_template.dart';

abstract class LetterTemplatesRepository {
  /// `GET /v1/letter-templates` — modèles globaux + ceux du cabinet.
  Future<Either<Failure, List<LetterTemplate>>> list();
}
