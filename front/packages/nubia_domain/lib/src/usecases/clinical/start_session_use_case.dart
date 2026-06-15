import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class StartSessionUseCase {
  final ClinicalSessionRepository _repository;

  const StartSessionUseCase(this._repository);

  Future<Either<Failure, ClinicalSession>> call(String appointmentId) =>
      _repository.startSession(appointmentId);
}
