import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';
import 'package:nubia_domain/src/repositories/session_port.dart';

class AddConsultationActUseCase {
  final ClinicalSessionRepository _repository;
  final SessionPort _session;

  const AddConsultationActUseCase(this._repository, this._session);

  Future<Either<Failure, ClinicalAct>> call({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  }) {
    if (!_session.canAccessClinical) {
      return Future.value(const Left(ClinicalAccessDenied()));
    }
    return _repository.addAct(
      consultationId: consultationId,
      ccamCode: ccamCode,
      label: label,
      tooth: tooth,
      amountCents: amountCents,
      included: included,
    );
  }
}
