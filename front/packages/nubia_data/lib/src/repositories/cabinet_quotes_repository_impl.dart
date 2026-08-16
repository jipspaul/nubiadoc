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
  Future<Either<Failure, List<CabinetQuote>>> list({
    int page = 1,
    String? patientId,
    int? limit,
    int? offset,
  }) async {
    try {
      final dtos = await _api.list(
        page: page,
        patientId: patientId,
        limit: limit,
        offset: offset,
      );
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les devis.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
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
    } catch (e) {
      return const Left(ParseFailure());
    }
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
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, CabinetQuoteStatus>> sendQuote(String id) async {
    try {
      final status = await _api.send(id);
      return Right(status);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (code == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (code == 409) {
        return const Left(ServerFailure(
          message: 'Ce devis a déjà été envoyé ou signé.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Envoi impossible.',
        statusCode: code,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
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
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
