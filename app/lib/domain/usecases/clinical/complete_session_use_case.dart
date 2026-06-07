import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';
import 'package:nubia_patient/domain/repositories/clinical_session_repository.dart';

@injectable
class CompleteSessionUseCase {
  final ClinicalSessionRepository _repository;

  const CompleteSessionUseCase(this._repository);

  Future<Either<Failure, SessionCompleteResult>> call(
          String consultationId) =>
      _repository.completeSession(consultationId);
}
