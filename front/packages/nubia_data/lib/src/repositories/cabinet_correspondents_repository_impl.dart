import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_correspondents/cabinet_correspondents_api.dart';
import 'package:nubia_domain/src/entities/cabinet_correspondent.dart';
import 'package:nubia_domain/src/repositories/cabinet_correspondents_repository.dart';

class CabinetCorrespondentsRepositoryImpl
    implements CabinetCorrespondentsRepository {
  final CabinetCorrespondentsApi _api;

  const CabinetCorrespondentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetCorrespondent>>> list() async {
    try {
      final dtos = await _api.list();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les correspondants.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetCorrespondent>> create({
    required String displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    try {
      final dto = await _api.create(
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(
            message: 'Le nom du correspondant est obligatoire ou un champ '
                'est invalide.',
          ),
        );
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetCorrespondent>> update(
    String id, {
    String? displayName,
    String? specialty,
    String? email,
    String? phone,
    String? address,
    String? rpps,
    String? notes,
  }) async {
    try {
      final dto = await _api.update(
        id,
        displayName: displayName,
        specialty: specialty,
        email: email,
        phone: phone,
        address: address,
        rpps: rpps,
        notes: notes,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 422) {
        return const Left(
          ValidationFailure(
            message: 'Le nom du correspondant est obligatoire ou un champ '
                'est invalide.',
          ),
        );
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de modifier le correspondant.',
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
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce correspondant est référencé par au moins un patient '
              'ou un courrier : impossible de le supprimer.',
          statusCode: 409,
          code: 'correspondent_in_use',
        ));
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de supprimer le correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CorrespondentStats>> getStats(String id) async {
    try {
      final dto = await _api.getStats(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Correspondant introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les statistiques du correspondant.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
