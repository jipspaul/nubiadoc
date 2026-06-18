import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/consultation/consultation_api.dart';
import 'package:nubia_domain/src/entities/consultation_context.dart';
import 'package:nubia_domain/src/repositories/consultation_repository.dart';

class ConsultationRepositoryImpl implements ConsultationRepository {
  final ConsultationApi _api;

  const ConsultationRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ConsultationContext>>> list(
      {int page = 1}) async {
    try {
      final dtos = await _api.list(page: page);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les consultations.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, ConsultationContext>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Consultation introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger la consultation.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, ConsultationContext>> create(
      ConsultationContext consultation) async {
    try {
      final dto = await _api.create(consultation);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer la consultation.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, ConsultationContext>> update(
      ConsultationContext consultation) async {
    try {
      final dto = await _api.update(consultation);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Consultation introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour la consultation.',
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
