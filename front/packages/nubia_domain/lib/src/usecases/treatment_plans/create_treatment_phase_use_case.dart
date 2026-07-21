import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/treatment_plans_repository.dart';

class CreateTreatmentPhaseUseCase {
  final TreatmentPlansRepository _repository;

  const CreateTreatmentPhaseUseCase(this._repository);

  Future<Either<Failure, String>> call(
    String planId,
    String title,
    int position,
  ) =>
      _repository.createPhase(planId, title, position);
}
