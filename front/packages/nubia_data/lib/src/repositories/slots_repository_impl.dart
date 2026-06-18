import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/slots/slots_api.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/repositories/slots_repository.dart';

class SlotsRepositoryImpl implements SlotsRepository {
  final SlotsApi _api;

  const SlotsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<Slot>>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  }) async {
    try {
      final dtos = await _api.list(
        from: from,
        to: to,
        practitionerId: practitionerId,
      );
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les créneaux.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Slot>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Créneau introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le créneau.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Slot>> create(Slot slot) async {
    try {
      final dto = await _api.create(slot);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le créneau.',
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, Slot>> update(Slot slot) async {
    try {
      final dto = await _api.update(slot);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Créneau introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le créneau.',
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
