import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/quote.dart';
import 'package:nubia_patient/domain/repositories/billing_repository.dart';

@injectable
class GetQuoteByIdUseCase {
  final BillingRepository _repository;

  const GetQuoteByIdUseCase(this._repository);

  Future<Either<Failure, Quote>> call(String id) =>
      _repository.getQuoteById(id);
}
