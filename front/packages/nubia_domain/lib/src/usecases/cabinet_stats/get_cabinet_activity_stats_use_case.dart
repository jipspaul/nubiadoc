import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_activity_stat.dart';
import 'package:nubia_domain/src/repositories/cabinet_stats_repository.dart';

class GetCabinetActivityStatsUseCase {
  final CabinetStatsRepository _repository;

  const GetCabinetActivityStatsUseCase(this._repository);

  Future<Either<Failure, List<CabinetActivityStat>>> call() =>
      _repository.getActivityStats();
}
