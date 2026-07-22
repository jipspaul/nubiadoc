import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/orthodontics_repository.dart';

class AddOrthodonticStepUseCase {
  final OrthodonticsRepository _repository;

  const AddOrthodonticStepUseCase(this._repository);

  Future<Either<Failure, String>> call(
    String treatmentId, {
    required int stepNumber,
    required String kind,
    String? conformityNotes,
  }) =>
      _repository.addStep(
        treatmentId,
        stepNumber: stepNumber,
        kind: kind,
        conformityNotes: conformityNotes,
      );
}
