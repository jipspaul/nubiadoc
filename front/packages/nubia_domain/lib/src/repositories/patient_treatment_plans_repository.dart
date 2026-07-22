import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_treatment_plan.dart';

abstract class PatientTreatmentPlansRepository {
  /// GET /v1/treatment-plans (#4261) — toutes les pages, cursor épuisé côté API.
  Future<Either<Failure, List<PatientTreatmentPlan>>> list();

  /// GET /v1/treatment-plans/:id (#4261) — détail avec phases/actes.
  Future<Either<Failure, PatientTreatmentPlan>> getById(String id);
}
