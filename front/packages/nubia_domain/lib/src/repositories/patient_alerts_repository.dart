import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_alert.dart';

abstract class PatientAlertsRepository {
  /// GET /v1/cabinet/patients/:id/alerts (#4093).
  Future<Either<Failure, List<PatientAlert>>> list(String patientId);
}
