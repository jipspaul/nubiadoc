import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/treatment_session.dart';
import 'package:nubia_domain/src/repositories/treatment_sessions_repository.dart';

class ProposeSessionSlotsUseCase {
  final TreatmentSessionsRepository _repository;

  const ProposeSessionSlotsUseCase(this._repository);

  Future<Either<Failure, List<ProposedSlot>>> call(
    String planId,
    String sessionId,
  ) =>
      _repository.proposeSlots(planId, sessionId);
}
