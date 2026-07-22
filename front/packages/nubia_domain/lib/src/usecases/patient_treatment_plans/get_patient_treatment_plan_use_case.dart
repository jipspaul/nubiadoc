import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_treatment_plan.dart';
import 'package:nubia_domain/src/repositories/patient_treatment_plans_repository.dart';

class GetPatientTreatmentPlanUseCase {
  final PatientTreatmentPlansRepository _repository;

  const GetPatientTreatmentPlanUseCase(this._repository);

  Future<Either<Failure, PatientTreatmentPlan>> call(String id) =>
      _repository.getById(id);
}
