import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/treatment_plan.dart';

abstract class TreatmentPlansRepository {
  Future<Either<Failure, List<TreatmentPlan>>> list(String patientId);

  /// Retourne l'id du plan créé.
  Future<Either<Failure, String>> create(String patientId, String title);

  /// Retourne l'id de la phase créée.
  Future<Either<Failure, String>> createPhase(
    String planId,
    String title,
    int position,
  );
}
