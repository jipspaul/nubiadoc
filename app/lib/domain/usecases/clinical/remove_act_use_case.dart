import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/repositories/clinical_session_repository.dart';

@injectable
class RemoveActUseCase {
  final ClinicalSessionRepository _repository;

  const RemoveActUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String consultationId,
    required String actId,
  }) =>
      _repository.removeAct(consultationId: consultationId, actId: actId);
}
