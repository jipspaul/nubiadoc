import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/quote_attachments_repository.dart';

class DeleteQuoteAttachmentUseCase {
  final QuoteAttachmentsRepository _repository;

  const DeleteQuoteAttachmentUseCase(this._repository);

  Future<Either<Failure, void>> call(String quoteId, String attachmentId) =>
      _repository.delete(quoteId, attachmentId);
}
