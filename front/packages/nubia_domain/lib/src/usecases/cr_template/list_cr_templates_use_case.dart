import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cr_template.dart';
import 'package:nubia_domain/src/repositories/cr_template_repository.dart';

class ListCrTemplatesUseCase {
  final CrTemplateRepository _repository;

  const ListCrTemplatesUseCase(this._repository);

  Future<Either<Failure, List<CrTemplate>>> call() =>
      _repository.listCrTemplates();
}
