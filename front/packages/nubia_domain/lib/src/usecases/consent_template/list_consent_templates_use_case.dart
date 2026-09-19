import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/consent_template.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/consent_template_repository.dart';

class ListConsentTemplatesUseCase {
  final ConsentTemplateRepository _repository;

  const ListConsentTemplatesUseCase(this._repository);

  Future<Either<Failure, List<ConsentTemplate>>> call() =>
      _repository.list();
}
