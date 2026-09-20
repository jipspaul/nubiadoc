import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/stock_import/stock_import_api.dart';
import 'package:nubia_domain/src/entities/stock_import_result.dart';
import 'package:nubia_domain/src/repositories/stock_import_repository.dart';

class StockImportRepositoryImpl implements StockImportRepository {
  final StockImportApi _api;

  const StockImportRepositoryImpl(this._api);

  @override
  Future<Either<Failure, StockImportResult>> importCsv(String csv) async {
    try {
      final dto = await _api.importCsv(csv);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'importer le fichier CSV.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
