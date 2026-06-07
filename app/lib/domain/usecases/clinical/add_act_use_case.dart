import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/clinical_session.dart';
import 'package:nubia_patient/domain/repositories/clinical_session_repository.dart';

@injectable
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
