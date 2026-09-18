import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/opportunity_category.dart';
import 'package:nubia_domain/src/repositories/cabinet_opportunities_repository.dart';

class GetCabinetOpportunitiesUseCase {
  final CabinetOpportunitiesRepository _repository;

  const GetCabinetOpportunitiesUseCase(this._repository);

  Future<Either<Failure, List<OpportunityCategory>>> call() =>
      _repository.getOpportunities();
}
