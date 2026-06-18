import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/secretariat/secretariat_api.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

class SecretariatRepositoryImpl implements SecretariatRepository {
  final SecretariatApi _api;

  const SecretariatRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Secretariat>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les secrétariats.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Secretariat>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Secrétariat introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le secrétariat.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Secretariat>> create(Secretariat secretariat) async {
    try {
      final dto = await _api.create(secretariat);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le secrétariat.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Secretariat>> update(Secretariat secretariat) async {
    try {
      final dto = await _api.update(secretariat);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Secrétariat introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le secrétariat.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Secretariat>> invite(String email) async {
    // TODO(FR3.7): wire to backend POST /v1/secretariat/invite.
    return const Left(ServerFailure(
      message: 'invite() not implemented yet',
      statusCode: 501,
    ));
  }
}
