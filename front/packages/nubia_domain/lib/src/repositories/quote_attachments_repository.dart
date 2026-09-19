import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';

abstract class QuoteAttachmentsRepository {
  /// `GET /v1/cabinet/quotes/:id/attachments`
  Future<Either<Failure, List<QuoteAttachment>>> list(String quoteId);

  /// `POST /v1/cabinet/quotes/:id/attachments` — exactement un de
  /// `documentId`/`templateRef` doit être renseigné.
  Future<Either<Failure, QuoteAttachment>> create(
    String quoteId, {
    required QuoteAttachmentKind kind,
    String? documentId,
    String? templateRef,
  });

  /// `DELETE /v1/cabinet/quotes/:id/attachments/:attachmentId`
  Future<Either<Failure, void>> delete(String quoteId, String attachmentId);
}
