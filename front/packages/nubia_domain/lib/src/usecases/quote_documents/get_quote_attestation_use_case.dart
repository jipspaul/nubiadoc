import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote_attestation.dart';
import 'package:nubia_domain/src/repositories/quote_attestation_repository.dart';

class GetQuoteAttestationUseCase {
  final QuoteAttestationRepository _repository;

  const GetQuoteAttestationUseCase(this._repository);

  Future<Either<Failure, QuoteAttestation?>> call(String quoteId) =>
      _repository.get(quoteId);
}
