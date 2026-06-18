import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/waiting_room/waiting_room_api.dart';
import 'package:nubia_domain/src/entities/waiting_room_entry.dart';
import 'package:nubia_domain/src/entities/waiting_list_entry.dart';
import 'package:nubia_domain/src/repositories/waiting_repository.dart';

class WaitingRoomRepositoryImpl implements WaitingRoomRepository {
  final WaitingRoomApi _api;

  const WaitingRoomRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<WaitingRoomEntry>>> list() async {
    try {
      final dtos = await _api.listWaitingRoom();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger la salle d'attente.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingRoomEntry>> getById(String id) async {
    try {
      final dto = await _api.getWaitingRoomById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée salle d\'attente introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'entrée.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingRoomEntry>> create(
      WaitingRoomEntry entry) async {
    try {
      final dto = await _api.createWaitingRoomEntry(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'ajouter à la salle d'attente.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingRoomEntry>> update(
      WaitingRoomEntry entry) async {
    try {
      final dto = await _api.updateWaitingRoomEntry(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée salle d\'attente introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de mettre à jour l'entrée.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingRoomEntry>> callNext() async {
    try {
      final dto = await _api.callNext();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'appeler le patient suivant.",
        statusCode: e.response?.statusCode,
      ));
    }
  }
}

class WaitingListRepositoryImpl implements WaitingListRepository {
  final WaitingRoomApi _api;

  const WaitingListRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<WaitingListEntry>>> list() async {
    try {
      final dtos = await _api.listWaitingList();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger la liste d'attente.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingListEntry>> getById(String id) async {
    try {
      final dto = await _api.getWaitingListById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée liste d\'attente introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'entrée.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingListEntry>> create(
      WaitingListEntry entry) async {
    try {
      final dto = await _api.createWaitingListEntry(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'ajouter à la liste d'attente.",
        statusCode: e.response?.statusCode,
      ));
    }
  }

  @override
  Future<Either<Failure, WaitingListEntry>> update(
      WaitingListEntry entry) async {
    try {
      final dto = await _api.updateWaitingListEntry(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée liste d\'attente introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de mettre à jour l'entrée.",
        statusCode: e.response?.statusCode,
      ));
    }
  }
}
