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
      return Left(ServerFailure(
        message: 'Impossible de démarrer la séance.',
        statusCode: e.response?.statusCode,
      ));
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
      return Left(ServerFailure(
        message: "Impossible d'ajouter l'acte.",
        statusCode: e.response?.statusCode,
      ));
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
    }
  }
}
