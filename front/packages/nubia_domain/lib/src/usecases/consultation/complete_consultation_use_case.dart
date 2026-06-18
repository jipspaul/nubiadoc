import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';
import 'package:nubia_domain/src/repositories/session_port.dart';

class CompleteConsultationUseCase {
  final ClinicalSessionRepository _repository;
  final SessionPort _session;

  const CompleteConsultationUseCase(this._repository, this._session);

  Future<Either<Failure, SessionCompleteResult>> call(String consultationId) {
    if (!_session.canAccessClinical) {
      return Future.value(const Left(ClinicalAccessDenied()));
    }
    return _repository.completeSession(consultationId);
  }
}
