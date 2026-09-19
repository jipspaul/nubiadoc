import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/letter_template.dart';
import 'package:nubia_domain/src/repositories/letter_templates_repository.dart';

class ListLetterTemplatesUseCase {
  final LetterTemplatesRepository _repository;

  const ListLetterTemplatesUseCase(this._repository);

  Future<Either<Failure, List<LetterTemplate>>> call() => _repository.list();
}
