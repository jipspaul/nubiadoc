import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/consultation_cr/consultation_cr_api.dart';
import 'package:nubia_domain/src/entities/consultation_cr.dart';
import 'package:nubia_domain/src/repositories/consultation_cr_repository.dart';

class ConsultationCrRepositoryImpl implements ConsultationCrRepository {
  final ConsultationCrApi _api;

  const ConsultationCrRepositoryImpl(this._api);

  @override
  Future<Either<Failure, ConsultationCr>> getConsultationCr(
    String consultationId,
  ) async {
    try {
      final dto = await _api.getConsultationCr(consultationId);
      return Right(dto.toDomain());
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
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Séance introuvable.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le compte rendu.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ConsultationCr>> saveConsultationCr({
    required String consultationId,
    String? templateId,
    required List<CrSectionEntry> sections,
  }) async {
    try {
      final dto = await _api.saveConsultationCr(
        consultationId: consultationId,
        templateId: templateId,
        sections: sections,
      );
      return Right(dto.toDomain());
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
      // #7154 — CR déjà finalisé (409 invalid_status) : plus de ré-édition
      // possible une fois figé.
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce compte rendu est déjà finalisé.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer le compte rendu.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ConsultationCr>> finalizeConsultationCr(
    String consultationId,
  ) async {
    try {
      final dto = await _api.finalizeConsultationCr(consultationId);
      return Right(dto.toDomain());
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
      // #7154 — rien à finaliser (422) ou déjà finalisé/séance annulée (409).
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(
          message: 'Renseignez au moins une section avant de finaliser.',
        ));
      }
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce compte rendu est déjà finalisé.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de finaliser le compte rendu.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
