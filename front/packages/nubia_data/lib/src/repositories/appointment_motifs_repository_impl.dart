import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/appointment_motifs/appointment_motifs_api.dart';
import 'package:nubia_domain/src/entities/appointment_motif.dart';
import 'package:nubia_domain/src/repositories/appointment_motifs_repository.dart';

class AppointmentMotifsRepositoryImpl implements AppointmentMotifsRepository {
  final AppointmentMotifsApi _api;

  const AppointmentMotifsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<AppointmentMotif>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les motifs de RDV.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, AppointmentMotif>> create({
    required String label,
    int? defaultDurationMinutes,
  }) async {
    try {
      final dto = await _api.create(
        label: label,
        defaultDurationMinutes: defaultDurationMinutes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Le libellé du motif est obligatoire.'),
        );
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Réservé aux administrateurs du cabinet.',
          statusCode: 403,
        ));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le motif.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, AppointmentMotif>> update(
    String id, {
    String? label,
    int? defaultDurationMinutes,
  }) async {
    try {
      final dto = await _api.update(
        id,
        label: label,
        defaultDurationMinutes: defaultDurationMinutes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(message: 'Le libellé du motif est obligatoire.'),
        );
      }
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Réservé aux administrateurs du cabinet.',
          statusCode: 403,
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Motif introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de modifier le motif.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> delete(String id) async {
    try {
      await _api.delete(id);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return const Left(ServerFailure(
          message: 'Réservé aux administrateurs du cabinet.',
          statusCode: 403,
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Motif introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de supprimer le motif.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
