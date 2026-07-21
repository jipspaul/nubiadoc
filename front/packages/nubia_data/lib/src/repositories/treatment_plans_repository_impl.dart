import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/treatment_plans/treatment_plans_api.dart';
import 'package:nubia_domain/src/entities/treatment_plan.dart';
import 'package:nubia_domain/src/repositories/treatment_plans_repository.dart';

class TreatmentPlansRepositoryImpl implements TreatmentPlansRepository {
  final TreatmentPlansApi _api;

  const TreatmentPlansRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<TreatmentPlan>>> list(String patientId) async {
    try {
      final dtos = await _api.list(patientId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les plans de traitement.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> create(
    String patientId,
    String title,
  ) async {
    try {
      final planId = await _api.create(patientId, title);
      return Right(planId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Titre requis.'));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Patient introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le plan de traitement.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> createPhase(
    String planId,
    String title,
    int position,
  ) async {
    try {
      final phaseId = await _api.createPhase(planId, title, position);
      return Right(phaseId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Titre requis.'));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Plan introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de créer la phase.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
