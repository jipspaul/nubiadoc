import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/lab_stats.dart';
import 'package:nubia_domain/src/repositories/cabinet_stats_repository.dart';

class GetCabinetLabStatsUseCase {
  final CabinetStatsRepository _repository;

  const GetCabinetLabStatsUseCase(this._repository);

  Future<Either<Failure, LabStats>> call({String? period}) =>
      _repository.getLabStats(period: period);
}
