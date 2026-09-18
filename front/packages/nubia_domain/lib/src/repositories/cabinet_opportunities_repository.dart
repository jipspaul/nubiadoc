import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/opportunity_category.dart';

abstract class CabinetOpportunitiesRepository {
  /// GET /v1/cabinet/opportunities (#7213/#7214).
  Future<Either<Failure, List<OpportunityCategory>>> getOpportunities();
}
