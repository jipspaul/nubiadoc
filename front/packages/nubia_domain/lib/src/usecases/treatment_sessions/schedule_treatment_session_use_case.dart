import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/treatment_sessions_repository.dart';

class ScheduleTreatmentSessionUseCase {
  final TreatmentSessionsRepository _repository;

  const ScheduleTreatmentSessionUseCase(this._repository);

  /// Retourne l'id du RDV créé.
  Future<Either<Failure, String>> call(
    String planId,
    String sessionId,
    String slotId,
  ) =>
      _repository.scheduleSession(planId, sessionId, slotId);
}
