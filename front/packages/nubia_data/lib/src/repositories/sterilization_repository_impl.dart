import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/sterilization/sterilization_api.dart';
import 'package:nubia_domain/src/entities/sterilization_cycle.dart';
import 'package:nubia_domain/src/entities/sterilized_pouch_use.dart';
import 'package:nubia_domain/src/repositories/sterilization_repository.dart';

class SterilizationRepositoryImpl implements SterilizationRepository {
  final SterilizationApi _api;

  const SterilizationRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<SterilizationCycle>>> listCycles() async {
    try {
      final dtos = await _api.listCycles();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les cycles de stérilisation.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> addPouch(
    String cycleId, {
    required String code,
    String? consultationActId,
  }) async {
    try {
      final pouchId = await _api.addPouch(
        cycleId,
        code: code,
        consultationActId: consultationActId,
      );
      return Right(pouchId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      // 409 pouch_code_already_used (#4139) : ce code a déjà été scanné
      // dans ce cabinet — message explicite plutôt qu'une erreur générique.
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Ce code a déjà été scanné.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer la pochette.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<int>>> fetchLabelsPdf(
    String cycleId, {
    int? shelfLifeDays,
  }) async {
    try {
      final bytes = await _api.fetchLabelsPdf(
        cycleId,
        shelfLifeDays: shelfLifeDays,
      );
      return Right(bytes);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) return const Left(UnauthorizedFailure());
      if (status == 404) return const Left(NotFoundFailure());
      if (status == 422) {
        return const Left(
          ValidationFailure(message: 'Durée de conservation invalide.'),
        );
      }
      return Left(ServerFailure(
        message: 'Impossible de générer les étiquettes.',
        statusCode: status,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, SterilizedPouchUse>> usePouch(
    String code, {
    required String patientId,
    String? consultationId,
  }) async {
    try {
      final dto = await _api.usePouch(
        code,
        patientId: patientId,
        consultationId: consultationId,
      );
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401) return const Left(UnauthorizedFailure());
      if (status == 404) return const Left(NotFoundFailure());
      if (status == 422) {
        return const Left(
          ValidationFailure(
            message: 'Cette séance appartient à un autre patient.',
          ),
        );
      }
      if (status == 409) {
        final data = e.response?.data;
        final code = data is Map ? data['code'] : null;
        if (code == 'pouch_cycle_non_conforme') {
          return const Left(ServerFailure(
            message: 'Cycle non conforme — ce sachet ne doit pas être '
                'utilisé.',
            statusCode: 409,
            code: 'pouch_cycle_non_conforme',
          ));
        }
        return const Left(ServerFailure(
          message: 'Ce sachet a déjà été utilisé sur un autre patient ou '
              'une autre séance.',
          statusCode: 409,
          code: 'pouch_already_used',
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de rattacher ce sachet.',
        statusCode: status,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
