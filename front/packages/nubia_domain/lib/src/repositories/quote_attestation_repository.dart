import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';

abstract class QuoteAttestationRepository {
  /// `GET /v1/cabinet/quotes/:id/attestation` — `null` si aucune attestation
  /// n'a encore été déposée sur ce devis (`404` côté API).
  Future<Either<Failure, QuoteAttestation?>> get(String quoteId);

  /// `POST /v1/cabinet/quotes/:id/attestation`.
  Future<Either<Failure, QuoteAttestation>> create(
    String quoteId, {
    required String body,
  });
}
