import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_briefs/cabinet_briefs_api.dart';
import 'package:nubia_domain/src/entities/cabinet_brief.dart';
import 'package:nubia_domain/src/repositories/cabinet_briefs_repository.dart';

class CabinetBriefsRepositoryImpl implements CabinetBriefsRepository {
  final CabinetBriefsApi _api;

  const CabinetBriefsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, CabinetBrief>> fetch({
    required String view,
    String? date,
  }) async {
    try {
      final dto = await _api.fetch(view: view, date: date);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Date invalide.'));
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le brief.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<int>>> fetchPdf({
    required String view,
    String? date,
  }) async {
    try {
      final bytes = await _api.fetchPdf(view: view, date: date);
      return Right(bytes);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 422) {
        return const Left(ValidationFailure(message: 'Date invalide.'));
      }
      return Left(ServerFailure(
        message: "Impossible de générer le PDF du brief.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
