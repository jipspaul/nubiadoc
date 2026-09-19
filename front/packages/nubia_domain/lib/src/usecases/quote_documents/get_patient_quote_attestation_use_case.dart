import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';
import 'package:nubia_domain/src/repositories/patient_quote_documents_repository.dart';

class GetPatientQuoteAttestationUseCase {
  final PatientQuoteDocumentsRepository _repository;

  const GetPatientQuoteAttestationUseCase(this._repository);

  Future<Either<Failure, QuoteAttestation?>> call(String quoteId) =>
      _repository.getAttestation(quoteId);
}
