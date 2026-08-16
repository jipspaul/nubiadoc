import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cash_collection_summary.dart';

abstract class CashCollectionRepository {
  /// GET /v1/cabinet/cash-collection/today (#5382).
  Future<Either<Failure, CashCollectionSummary>> getTodaySummary();
}
