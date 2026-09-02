import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/clinical/clinical_session_api.dart';
import 'package:nubia_domain/src/entities/clinical_session.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class ClinicalSessionRepositoryImpl implements ClinicalSessionRepository {
  final ClinicalSessionApi _api;

  const ClinicalSessionRepositoryImpl(this._api);

  @override
  Future<Either<Failure, ClinicalSession>> startSession(
      String appointmentId) async {
    try {
      final dto = await _api.startSession(appointmentId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // #6254 — Le 409 recouvre trois codes distincts (api/src/scheduling.rs:
      // 1877-1942) : `too_early`/`out_of_window` (fenêtre de démarrage ±60min
      // ratée) n'ont rien à voir avec `invalid_status` (séance déjà ouverte)
      // et doivent afficher un message différent, sans passer par le repli
      // `_resumeExistingSession`.
      if (e.response?.statusCode == 409) {
        final apiCode = e.response?.data is Map
            ? (e.response!.data as Map)['code'] as String?
            : null;
        if (apiCode == 'too_early') {
          return const Left(ValidationFailure(
            message:
                'Il est trop tôt pour démarrer cette séance. Réessayez plus près de l\'heure du rendez-vous.',
          ));
        }
        if (apiCode == 'out_of_window') {
          return const Left(ValidationFailure(
            message:
                'Ce rendez-vous est passé, il ne peut plus être démarré.',
          ));
        }
        // #3400 — La séance est déjà démarrée (409 invalid_status). Ce n'est
        // pas une erreur fatale : on récupère la séance `in_progress` liée à
        // ce RDV pour permettre la reprise (navigation vers la consultation
        // existante).
        final resumed = await _resumeExistingSession(appointmentId);
        if (resumed != null) return Right(resumed);
        return const Left(ServerFailure(
          message: 'Séance déjà démarrée.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de démarrer la séance.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  /// Retrouve la séance `in_progress` d'un rendez-vous déjà démarré (#3400).
  /// Retourne `null` si aucune séance correspondante n'est trouvable.
  Future<ClinicalSession?> _resumeExistingSession(String appointmentId) async {
    try {
      final sessions = await _api.listSessions(status: 'in_progress');
      for (final dto in sessions) {
        if (dto.appointmentId == appointmentId) return dto.toDomain();
      }
    } catch (_) {
      // On reste silencieux : l'appelant retombera sur le message 409.
    }
    return null;
  }

  @override
  Future<Either<Failure, List<ClinicalSession>>> listSessions({
    String? patientId,
    String? status,
  }) async {
    try {
      final dtos =
          await _api.listSessions(patientId: patientId, status: status);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'historique des consultations.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ClinicalSession>> getSession(
      String consultationId) async {
    try {
      final dto = await _api.getSession(consultationId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Séance introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger la séance.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ClinicalAct>> addAct({
    required String consultationId,
    required String ccamCode,
    required String label,
    String? tooth,
    int? amountCents,
    bool included = false,
  }) async {
    try {
      final dto = await _api.addAct(
        consultationId: consultationId,
        ccamCode: ccamCode,
        label: label,
        tooth: tooth,
        amountCents: amountCents,
        included: included,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // #3403 — Ajout sur la séance d'un confrère : le back répond 403. On
      // remonte un message explicite (au lieu d'un échec silencieux côté UI).
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Action non autorisée.',
          statusCode: 403,
        ));
      }
      // #4057/#4058 — alerte clinique bloquante (moteur d'alertes API) :
      // 409 { code: "clinical_risk_warning", message: "..." }. Distingué de
      // ServerFailure pour que l'UI affiche un dialogue bloquant dédié.
      if (e.response?.statusCode == 409 &&
          e.response?.data is Map &&
          (e.response?.data as Map)['code'] == 'clinical_risk_warning') {
        final message = (e.response?.data as Map)['message'] as String? ??
            'Alerte clinique : acte bloqué.';
        return Left(ClinicalRiskWarningFailure(message));
      }
      return Left(ServerFailure(
        message: "Impossible d'ajouter l'acte.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> removeAct({
    required String consultationId,
    required String actId,
  }) async {
    try {
      await _api.removeAct(consultationId: consultationId, actId: actId);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de supprimer l'acte.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> saveNote({
    required String consultationId,
    required String note,
  }) async {
    try {
      await _api.saveNote(consultationId: consultationId, note: note);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Action non autorisée.',
          statusCode: 403,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer la note.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, SessionCompleteResult>> completeSession(
      String consultationId) async {
    try {
      final result = await _api.completeSession(consultationId);
      return Right(result);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de terminer la séance.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
