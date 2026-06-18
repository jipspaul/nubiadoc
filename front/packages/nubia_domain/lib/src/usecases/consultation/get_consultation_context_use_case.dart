import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/consultation_context.dart';
import 'package:nubia_domain/src/repositories/consultation_repository.dart';
import 'package:nubia_domain/src/repositories/session_port.dart';

class GetConsultationContextUseCase {
  final ConsultationRepository _repository;
  final SessionPort _session;

  const GetConsultationContextUseCase(this._repository, this._session);

  Future<Either<Failure, ConsultationContext>> call(String id) {
    if (!_session.canAccessClinical) {
      return Future.value(const Left(ClinicalAccessDenied()));
    }
    return _repository.getById(id);
  }
}
