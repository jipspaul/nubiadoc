import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/quote_attestation/quote_attestation_api.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';
import 'package:nubia_domain/src/repositories/quote_attestation_repository.dart';

class QuoteAttestationRepositoryImpl implements QuoteAttestationRepository {
  final QuoteAttestationApi _api;

  const QuoteAttestationRepositoryImpl(this._api);

  @override
  Future<Either<Failure, QuoteAttestation?>> get(String quoteId) async {
    try {
      final dto = await _api.get(quoteId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      // Aucune attestation déposée sur ce devis → 404, pas une erreur : la
      // section « attestation » l'affiche simplement comme absente.
      if (e.response?.statusCode == 404) {
        return const Right(null);
      }
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      return Left(ServerFailure(
        message: "Impossible de charger l'attestation d'information.",
        statusCode: e.response?.statusCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, QuoteAttestation>> create(
    String quoteId, {
    required String body,
  }) async {
    try {
      final dto = await _api.create(quoteId, body: body);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final apiCode = e.response?.data is Map
          ? (e.response!.data as Map)['code'] as String?
          : null;
      if (statusCode == 404) {
        return const Left(NotFoundFailure('Devis introuvable.'));
      }
      if (statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (statusCode == 409 && apiCode == 'quote_locked') {
        return const Left(ServerFailure(
          message:
              'Le devis est déjà signé, impossible de déposer une attestation.',
          statusCode: 409,
          code: 'quote_locked',
        ));
      }
      if (statusCode == 409 && apiCode == 'attestation_already_pending') {
        return const Left(ServerFailure(
          message:
              "Une attestation est déjà en attente de signature pour ce devis.",
          statusCode: 409,
          code: 'attestation_already_pending',
        ));
      }
      if (statusCode == 422) {
        return const Left(ValidationFailure(
          message: "Texte d'attestation invalide.",
        ));
      }
      return Left(ServerFailure(
        message: "Impossible de créer l'attestation d'information.",
        statusCode: statusCode,
        code: apiCode,
      ));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }
}
