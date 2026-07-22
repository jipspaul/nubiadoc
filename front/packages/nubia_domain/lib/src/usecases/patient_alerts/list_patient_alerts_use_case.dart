import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_alert.dart';
import 'package:nubia_domain/src/repositories/patient_alerts_repository.dart';

class ListPatientAlertsUseCase {
  final PatientAlertsRepository _repository;

  const ListPatientAlertsUseCase(this._repository);

  Future<Either<Failure, List<PatientAlert>>> call(String patientId) =>
      _repository.list(patientId);
}
