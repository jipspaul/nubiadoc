import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class ListClinicalSessionsUseCase {
  final ClinicalSessionRepository _repository;
  const ListClinicalSessionsUseCase(this._repository);

  Future<Either<Failure, List<ClinicalSession>>> call({
    String? patientId,
    String? status,
  }) =>
      _repository.listSessions(patientId: patientId, status: status);
}
