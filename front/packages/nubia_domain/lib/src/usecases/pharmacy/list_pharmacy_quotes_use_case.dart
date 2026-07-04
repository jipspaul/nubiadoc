import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_quote.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_quotes_repository.dart';

class ListPharmacyQuotesUseCase {
  final PharmacyQuotesRepository _repository;

  const ListPharmacyQuotesUseCase(this._repository);

  Future<Either<Failure, List<PharmacyQuote>>> call() => _repository.list();
}
