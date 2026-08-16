import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cash_collection_summary.dart';
import 'package:nubia_domain/src/repositories/cash_collection_repository.dart';

class GetCashCollectionSummaryUseCase {
  final CashCollectionRepository _repository;

  const GetCashCollectionSummaryUseCase(this._repository);

  Future<Either<Failure, CashCollectionSummary>> call() =>
      _repository.getTodaySummary();
}
