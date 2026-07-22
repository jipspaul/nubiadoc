import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_billing_stats.dart';
import 'package:nubia_domain/src/repositories/cabinet_stats_repository.dart';

class GetCabinetBillingStatsUseCase {
  final CabinetStatsRepository _repository;

  const GetCabinetBillingStatsUseCase(this._repository);

  Future<Either<Failure, CabinetBillingStats>> call() =>
      _repository.getBillingStats();
}
