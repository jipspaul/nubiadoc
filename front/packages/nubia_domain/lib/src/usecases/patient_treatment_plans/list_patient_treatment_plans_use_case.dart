import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_treatment_plan.dart';
import 'package:nubia_domain/src/repositories/patient_treatment_plans_repository.dart';

class ListPatientTreatmentPlansUseCase {
  final PatientTreatmentPlansRepository _repository;

  const ListPatientTreatmentPlansUseCase(this._repository);

  Future<Either<Failure, List<PatientTreatmentPlan>>> call() =>
      _repository.list();
}
