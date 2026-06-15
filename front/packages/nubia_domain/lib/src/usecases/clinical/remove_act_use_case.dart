import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class RemoveActUseCase {
  final ClinicalSessionRepository _repository;

  const RemoveActUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String consultationId,
    required String actId,
  }) =>
      _repository.removeAct(consultationId: consultationId, actId: actId);
}
