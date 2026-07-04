import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/entities/parsed_search.dart';
import 'package:nubia_domain/src/entities/provider_result.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';
import 'package:nubia_data/src/remote/search/search_api.dart';

class SearchRepositoryImpl implements SearchRepository {
  final SearchApi _api;

  const SearchRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ProviderResult>>> searchProviders({
    required String query,
  }) async {
    try {
      final dtos = await _api.searchProviders(query: query);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la recherche de praticiens.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, ParsedSearch>> parseSearch(String query) async {
    try {
      final dto = await _api.parseSearch(query);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      // Endpoint pas encore déployé (404) ou autre erreur serveur : l'appelant
      // retombe sur la recherche texte brut.
      return Left(ServerFailure(
        message: 'Interprétation de la recherche indisponible.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, List<Slot>>> searchSlots({
    required String providerId,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final dtos = await _api.searchSlots(
        providerId: providerId,
        from: from,
        to: to,
      );
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return const Left(OfflineFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors du chargement des créneaux.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> holdSlot(String slotId) async {
    try {
      final token = await _api.holdSlot(slotId);
      return Right(token);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        return const Left(ValidationFailure(
          message: 'Ce créneau n\'est plus disponible.',
        ));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la réservation du créneau.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, String>> confirmBooking({
    required String slotId,
    required String holdToken,
    required String motif,
    required String idempotencyKey,
  }) async {
    try {
      final appointmentId = await _api.confirmBooking(
        slotId: slotId,
        holdToken: holdToken,
        motif: motif,
        idempotencyKey: idempotencyKey,
      );
      return Right(appointmentId);
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        return const Left(ValidationFailure(
          message: 'Ce créneau n\'est plus disponible.',
        ));
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: 'Erreur lors de la réservation du rendez-vous.',
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
