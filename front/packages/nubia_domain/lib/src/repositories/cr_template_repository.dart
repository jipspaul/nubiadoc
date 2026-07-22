import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cr_template.dart';

abstract class CrTemplateRepository {
  /// GET /v1/cabinet/cr-templates (#4124).
  Future<Either<Failure, List<CrTemplate>>> listCrTemplates();
}
