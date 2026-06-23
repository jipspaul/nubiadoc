import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_agenda/cabinet_agenda_api.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';
import 'package:nubia_domain/src/repositories/cabinet_agenda_repository.dart';

class CabinetAgendaRepositoryImpl implements CabinetAgendaRepository {
  final CabinetAgendaApi _api;

  const CabinetAgendaRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<AgendaEntry>>> list({
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
        message: "Impossible de charger l'agenda.",
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, AgendaEntry>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée agenda introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'entrée agenda.",
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, AgendaEntry>> create(AgendaEntry entry) async {
    try {
      final dto = await _api.create(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'entrée agenda.",
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, AgendaEntry>> update(AgendaEntry entry) async {
    try {
      final dto = await _api.update(entry);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Entrée agenda introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de mettre à jour l'entrée agenda.",
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }
}
