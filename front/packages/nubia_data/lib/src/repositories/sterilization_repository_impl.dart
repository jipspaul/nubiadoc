import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/sterilization/sterilization_api.dart';
import 'package:nubia_domain/src/entities/sterilization_cycle.dart';
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
}
