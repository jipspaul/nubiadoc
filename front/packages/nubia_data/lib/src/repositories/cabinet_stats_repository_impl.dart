import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_stats/cabinet_stats_api.dart';
import 'package:nubia_domain/src/entities/cabinet_activity_stat.dart';
import 'package:nubia_domain/src/entities/cabinet_billing_stats.dart';
import 'package:nubia_domain/src/repositories/cabinet_stats_repository.dart';

class CabinetStatsRepositoryImpl implements CabinetStatsRepository {
  final CabinetStatsApi _api;

  const CabinetStatsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetActivityStat>>> getActivityStats() async {
    try {
      final dtos = await _api.getActivityStats();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'activité du cabinet.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetBillingStats>> getBillingStats() async {
    try {
      final dto = await _api.getBillingStats();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger la facturation du cabinet.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
