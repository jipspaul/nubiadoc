import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_quotes_repository.dart';

/// Acceptation ou refus d'un devis d'officine (côté patient).
class DecidePharmacyQuoteUseCase {
  final PharmacyQuotesRepository _repository;

  const DecidePharmacyQuoteUseCase(this._repository);

  Future<Either<Failure, PharmacyQuote>> call(String id,
          {required bool accept}) =>
      _repository.decide(id, accept: accept);
}
