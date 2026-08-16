import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cash_collection/cash_collection_api.dart';
import 'package:nubia_domain/src/entities/cash_collection_summary.dart';
import 'package:nubia_domain/src/repositories/cash_collection_repository.dart';

class CashCollectionRepositoryImpl implements CashCollectionRepository {
  final CashCollectionApi _api;

  const CashCollectionRepositoryImpl(this._api);

  @override
  Future<Either<Failure, CashCollectionSummary>> getTodaySummary() async {
    try {
      final dto = await _api.getTodaySummary();
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les encaissements du jour.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
