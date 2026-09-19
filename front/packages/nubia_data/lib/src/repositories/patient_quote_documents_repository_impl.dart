import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_data/src/remote/quote_documents/patient_quote_documents_api.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';
import 'package:nubia_domain/src/repositories/patient_quote_documents_repository.dart';

class PatientQuoteDocumentsRepositoryImpl
    implements PatientQuoteDocumentsRepository {
  final PatientQuoteDocumentsApi _api;

  const PatientQuoteDocumentsRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<QuoteAttachment>>> listAttachments(
      String quoteId) async {
    try {
      final dtos = await _api.listAttachments(quoteId);
      return Right(dtos.map((d) => d.toDomain()).toList());
    } on DioException catch (e) {
      return Left(_mapReadError(
          e, 'Impossible de charger les pièces jointes du devis.'));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, QuoteAttestation?>> getAttestation(
      String quoteId) async {
    try {
      final dto = await _api.getAttestation(quoteId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      // Aucune attestation déposée sur ce devis → 404, pas une erreur.
      if (e.response?.statusCode == 404) {
        return const Right(null);
      }
      return Left(_mapReadError(
          e, "Impossible de charger l'attestation d'information."));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  @override
  Future<Either<Failure, QuoteAttestation>> signAttestation(
      String quoteId) async {
    try {
      await _api.signAttestation(quoteId);
      final dto = await _api.getAttestation(quoteId);
      return Right(dto.toDomain());
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return const Left(
            NotFoundFailure('Aucune attestation à signer pour ce devis.'));
      }
      return Left(_mapReadError(
          e, "Erreur lors de la signature de l'attestation d'information."));
    } catch (e) {
      return const Left(ParseFailure());
    }
  }

  Failure _mapReadError(DioException e, String defaultMessage) {
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const OfflineFailure();
    }
    if (e.response?.statusCode == 401) return const UnauthorizedFailure();
    if (e.response?.statusCode == 404) {
      return const NotFoundFailure('Devis introuvable.');
    }
    return ServerFailure(
      message: defaultMessage,
      statusCode: e.response?.statusCode,
    );
  }
}
