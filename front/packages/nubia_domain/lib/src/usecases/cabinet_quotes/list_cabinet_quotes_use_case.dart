import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_quote.dart';
import 'package:nubia_domain/src/repositories/cabinet_quotes_repository.dart';

class ListCabinetQuotesUseCase {
  final CabinetQuotesRepository _repository;

  const ListCabinetQuotesUseCase(this._repository);

  Future<Either<Failure, List<CabinetQuote>>> call({int page = 1}) =>
      _repository.list(page: page);
}
