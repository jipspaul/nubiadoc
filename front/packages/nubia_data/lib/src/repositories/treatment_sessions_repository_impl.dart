import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/treatment_sessions/treatment_sessions_api.dart';
import 'package:nubia_domain/src/entities/treatment_session.dart';
import 'package:nubia_domain/src/repositories/treatment_sessions_repository.dart';

class TreatmentSessionsRepositoryImpl implements TreatmentSessionsRepository {
  final TreatmentSessionsApi _api;

  const TreatmentSessionsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<TreatmentSession>>> proposeSessions(
    String planId, {
    int? defaultDurationMin,
  }) async {
    try {
      final dtos = await _api.proposeSessions(
        planId,
        defaultDurationMin: defaultDurationMin,
      );
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Plan de traitement introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 422 : plan terminé, ou tous les actes du plan sont déjà affectés à
      // une séance existante — rien à répartir.
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
          message: "Aucun acte à répartir en séances pour ce plan.",
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de proposer les séances.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<ProposedSlot>>> proposeSlots(
    String planId,
    String sessionId,
  ) async {
    try {
      final dtos = await _api.proposeSlots(planId, sessionId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(
            NotFoundFailure('Plan ou séance introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 422 : aucun praticien résolu (ni fourni, ni sur le plan).
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
          message: 'Aucun praticien associé à ce plan.',
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les créneaux proposés.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> scheduleSession(
    String planId,
    String sessionId,
    String slotId,
  ) async {
    try {
      final appointmentId =
          await _api.scheduleSession(planId, sessionId, slotId);
      return Right(appointmentId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Plan ou séance introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 409 : séance déjà programmée (course avec un autre onglet) ou
      // créneau pris entre-temps — même message générique, l'appelant
      // recharge la liste des séances/créneaux.
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce créneau vient d\'être pris, choisissez-en un autre.',
          statusCode: 409,
        ));
      }
      // 422 : créneau plus court que la durée de la séance.
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
          message: 'Ce créneau est trop court pour la durée de la séance.',
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
