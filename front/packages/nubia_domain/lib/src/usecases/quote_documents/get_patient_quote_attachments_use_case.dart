import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attachment.dart';
import 'package:nubia_domain/src/repositories/patient_quote_documents_repository.dart';

class GetPatientQuoteAttachmentsUseCase {
  final PatientQuoteDocumentsRepository _repository;

  const GetPatientQuoteAttachmentsUseCase(this._repository);

  Future<Either<Failure, List<QuoteAttachment>>> call(String quoteId) =>
      _repository.listAttachments(quoteId);
}
