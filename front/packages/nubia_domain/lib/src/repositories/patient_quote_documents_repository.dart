import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';

/// Pièces jointes et attestation d'information d'un devis, vues côté
/// patient — lecture seule, la signature de l'attestation étant la seule
/// écriture possible (#7201/#7203).
abstract class PatientQuoteDocumentsRepository {
  /// `GET /v1/quotes/:id/attachments`.
  Future<Either<Failure, List<QuoteAttachment>>> listAttachments(
      String quoteId);

  /// `GET /v1/quotes/:id/attestation` — `null` si aucune attestation n'a
  /// encore été déposée sur ce devis (`404` côté API).
  Future<Either<Failure, QuoteAttestation?>> getAttestation(String quoteId);

  /// `POST /v1/quotes/:id/attestation/sign`.
  Future<Either<Failure, QuoteAttestation>> signAttestation(String quoteId);
}
