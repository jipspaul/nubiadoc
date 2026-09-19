import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/repositories/quote_attachments_repository.dart';

class CreateQuoteAttachmentUseCase {
  final QuoteAttachmentsRepository _repository;

  const CreateQuoteAttachmentUseCase(this._repository);

  Future<Either<Failure, QuoteAttachment>> call(
    String quoteId, {
    required QuoteAttachmentKind kind,
    String? documentId,
    String? templateRef,
  }) =>
      _repository.create(
        quoteId,
        kind: kind,
        documentId: documentId,
        templateRef: templateRef,
      );
}
