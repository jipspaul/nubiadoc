import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';
import 'package:nubia_domain/src/repositories/quote_attestation_repository.dart';

class CreateQuoteAttestationUseCase {
  final QuoteAttestationRepository _repository;

  const CreateQuoteAttestationUseCase(this._repository);

  Future<Either<Failure, QuoteAttestation>> call(
    String quoteId, {
    required String body,
  }) =>
      _repository.create(quoteId, body: body);
}
