import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

class GetCabinetQuoteUseCase {
  final CabinetQuotesRepository _repository;

  const GetCabinetQuoteUseCase(this._repository);

  Future<Either<Failure, CabinetQuote>> call(String id) =>
      _repository.getById(id);
}
