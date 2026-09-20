import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/stock_locations/stock_locations_api.dart';
import 'package:nubia_domain/src/entities/stock_location.dart';
import 'package:nubia_domain/src/entities/stock_item_location.dart';
import 'package:nubia_domain/src/repositories/stock_locations_repository.dart';

class StockLocationsRepositoryImpl implements StockLocationsRepository {
  final StockLocationsApi _api;

  const StockLocationsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<StockLocation>>> listLocations() async {
    try {
      final dtos = await _api.listLocations();
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Impossible de charger les localisations de stock.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> createLocation(String name) async {
    try {
      return Right(await _api.createLocation(name));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 409) {
        return const Left(ServerFailure(
          message: 'Une localisation porte déjà ce nom.',
          statusCode: 409,
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de créer la localisation.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<StockItemLocation>>> listItemLocations(
    String itemId,
  ) async {
    try {
      final dtos = await _api.listItemLocations(itemId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger le stock par salle de cet article.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, void>> setItemLocationThreshold(
    String itemId,
    String locationId, {
    int? threshold,
  }) async {
    try {
      await _api.setItemLocationThreshold(itemId, locationId,
          threshold: threshold);
      return const Right(null);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      return Left(ServerFailure(
        message: "Impossible d'enregistrer le seuil d'alerte.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, (int, int)>> transfer(
    String itemId, {
    required String fromLocationId,
    required String toLocationId,
    required int quantity,
  }) async {
    try {
      return Right(await _api.transfer(
        itemId,
        fromLocationId: fromLocationId,
        toLocationId: toLocationId,
        quantity: quantity,
      ));
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Left(NotFoundFailure());
      }
      if (e.response?.statusCode == 422 &&
          e.response?.data is Map &&
          (e.response?.data as Map)['code'] == 'insufficient_stock') {
        return const Left(ServerFailure(
          message: 'Quantité insuffisante dans la localisation source.',
          statusCode: 422,
          code: 'insufficient_stock',
        ));
      }
      return Left(ServerFailure(
        message: 'Impossible de transférer le stock.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
