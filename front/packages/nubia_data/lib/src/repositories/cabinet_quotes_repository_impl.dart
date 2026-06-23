import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_api.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

class CabinetQuotesRepositoryImpl implements CabinetQuotesRepository {
  final CabinetQuotesApi _api;

  const CabinetQuotesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<CabinetQuote>>> list({int page = 1}) async {
    try {
      final dtos = await _api.list(page: page);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les devis.',
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, CabinetQuote>> getById(String id) async {
    try {
      final dto = await _api.getById(id);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger le devis.',
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, CabinetQuote>> create(CabinetQuote quote) async {
    try {
      final dto = await _api.create(quote);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de créer le devis.',
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }

  @override
  Future<Either<Failure, CabinetQuote>> update(CabinetQuote quote) async {
    try {
      final dto = await _api.update(quote);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de mettre à jour le devis.',
        statusCode: e.response?.statusCode,
      ));
    }
    } catch (e) {
      return const Left(ParseFailure());
  }
}
