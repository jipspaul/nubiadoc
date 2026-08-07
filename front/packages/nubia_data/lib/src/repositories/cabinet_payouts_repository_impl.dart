import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_payouts/cabinet_payouts_api.dart';
import 'package:nubia_domain/src/entities/cabinet_payout.dart';
import 'package:nubia_domain/src/repositories/cabinet_payouts_repository.dart';

class CabinetPayoutsRepositoryImpl implements CabinetPayoutsRepository {
  final CabinetPayoutsApi _api;

  const CabinetPayoutsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetPayout>>> getPayouts() async {
    try {
      final dtos = await _api.getPayouts();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les virements.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
