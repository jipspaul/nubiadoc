import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_quotes_repository.dart';

class RemindPharmacyQuoteUseCase {
  final PharmacyQuotesRepository _repository;

  const RemindPharmacyQuoteUseCase(this._repository);

  Future<Either<Failure, PharmacyQuote>> call(String id) =>
      _repository.remind(id);
}
