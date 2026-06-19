import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';

abstract class ClinicalSessionRepository {
  /// POST /v1/cabinet/appointments/{id}/start
  Future<Either<Failure, ClinicalSession>> startSession(String appointmentId);

  /// GET /v1/cabinet/consultations/{id}
  Future<Either<Failure, ClinicalSession>> getSession(String consultationId);

  /// POST /v1/cabinet/consultations/{id}/acts
  Future<Either<Failure, ClinicalAct>> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  });

  /// DELETE /v1/cabinet/consultations/{id}/acts/{actId}
  Future<Either<Failure, void>> removeAct({
    required String consultationId,
    required String actId,
  });

  /// POST /v1/cabinet/consultations/{id}/complete
  Future<Either<Failure, SessionCompleteResult>> completeSession(
      String consultationId);
}
