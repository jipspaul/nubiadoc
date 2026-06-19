import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class CompleteSessionUseCase {
  final ClinicalSessionRepository _repository;

  const CompleteSessionUseCase(this._repository);

  Future<Either<Failure, SessionCompleteResult>> call(
          String consultationId) =>
      _repository.completeSession(consultationId);
}
