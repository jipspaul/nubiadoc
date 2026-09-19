import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/generated_letter.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/letters_repository.dart';

class GenerateLetterUseCase {
  final LettersRepository _repository;

  const GenerateLetterUseCase(this._repository);

  Future<Either<Failure, GeneratedLetter>> call(
    String patientId, {
    required String templateId,
    Map<String, String> overrides = const {},
  }) =>
      _repository.generate(
        patientId,
        templateId: templateId,
        overrides: overrides,
      );
}
