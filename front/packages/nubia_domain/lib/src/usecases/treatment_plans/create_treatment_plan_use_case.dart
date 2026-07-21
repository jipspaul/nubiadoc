import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/treatment_plans_repository.dart';

class CreateTreatmentPlanUseCase {
  final TreatmentPlansRepository _repository;

  const CreateTreatmentPlanUseCase(this._repository);

  Future<Either<Failure, String>> call(String patientId, String title) =>
      _repository.create(patientId, title);
}
