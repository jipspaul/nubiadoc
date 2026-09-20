import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/treatment_session.dart';
import 'package:nubia_domain/src/repositories/treatment_sessions_repository.dart';

class ProposeTreatmentSessionsUseCase {
  final TreatmentSessionsRepository _repository;

  const ProposeTreatmentSessionsUseCase(this._repository);

  Future<Either<Failure, List<TreatmentSession>>> call(
    String planId, {
    int? defaultDurationMin,
  }) =>
      _repository.proposeSessions(
        planId,
        defaultDurationMin: defaultDurationMin,
      );
}
