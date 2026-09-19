import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/repositories/quote_attachments_repository.dart';

class ListQuoteAttachmentsUseCase {
  final QuoteAttachmentsRepository _repository;

  const ListQuoteAttachmentsUseCase(this._repository);

  Future<Either<Failure, List<QuoteAttachment>>> call(String quoteId) =>
      _repository.list(quoteId);
}
