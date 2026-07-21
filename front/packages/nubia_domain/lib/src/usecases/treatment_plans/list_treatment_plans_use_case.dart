import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/treatment_plan.dart';
import 'package:nubia_domain/src/repositories/treatment_plans_repository.dart';

class ListTreatmentPlansUseCase {
  final TreatmentPlansRepository _repository;

  const ListTreatmentPlansUseCase(this._repository);

  Future<Either<Failure, List<TreatmentPlan>>> call(String patientId) =>
      _repository.list(patientId);
}
