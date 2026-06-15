import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class AddActUseCase {
  final ClinicalSessionRepository _repository;

  const AddActUseCase(this._repository);

  Future<Either<Failure, ClinicalAct>> call({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  }) =>
      _repository.addAct(
        consultationId: consultationId,
        ccamCode: ccamCode,
        label: label,
        tooth: tooth,
        amountCents: amountCents,
        included: included,
      );
}
