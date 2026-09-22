import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/maintenance_stats.dart';
import 'package:nubia_domain/src/repositories/maintenance_repository.dart';

class GetMaintenanceStatsUseCase {
  final MaintenanceRepository _repository;

  const GetMaintenanceStatsUseCase(this._repository);

  Future<Either<Failure, MaintenanceStats>> call() => _repository.getStats();
}
