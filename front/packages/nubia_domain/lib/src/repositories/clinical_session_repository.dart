import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';

abstract class ClinicalSessionRepository {
  /// POST /v1/cabinet/appointments/{id}/start
  Future<Either<Failure, ClinicalSession>> startSession(String appointmentId);

  /// GET /v1/cabinet/consultations/{id}
  Future<Either<Failure, ClinicalSession>> getSession(String consultationId);

  /// POST /v1/cabinet/consultations/{id}/acts
  ///
  /// [riskAcknowledged] (#7911) : à `true` pour rejouer l'ajout après que le
  /// praticien a acquitté l'alerte clinique (#4057) reçue sur une première
  /// tentative — sans ça, l'API renvoie à nouveau `409 clinical_risk_warning`
  /// indéfiniment pour le même acte.
  Future<Either<Failure, ClinicalAct>> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
    bool riskAcknowledged = false,
  });

  /// DELETE /v1/cabinet/consultations/{id}/acts/{actId}
  Future<Either<Failure, void>> removeAct({
    required String consultationId,
    required String actId,
  });

  /// POST /v1/cabinet/consultations/{id}/complete
  Future<Either<Failure, SessionCompleteResult>> completeSession(
      String consultationId);

  /// PUT /v1/cabinet/consultations/{id}/note
  Future<Either<Failure, void>> saveNote({
    required String consultationId,
    required String note,
  });

  /// GET /v1/cabinet/consultations — historique des séances du cabinet (#3232).
  /// Résumés sans note clinique (le détail passe par [getSession]) ; `acts` ne
  /// contient que le premier acte de la séance (#4937), pas la liste complète.
  Future<Either<Failure, List<ClinicalSession>>> listSessions({
    String? patientId,
    String? status,
  });
}
