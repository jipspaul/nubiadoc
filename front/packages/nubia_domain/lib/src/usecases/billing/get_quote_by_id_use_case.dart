import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/quote.dart';
import 'package:nubia_domain/src/repositories/billing_repository.dart';

class GetQuoteByIdUseCase {
  final BillingRepository _repository;

  const GetQuoteByIdUseCase(this._repository);

  Future<Either<Failure, Quote>> call(String id) =>
      _repository.getQuoteById(id);
}
