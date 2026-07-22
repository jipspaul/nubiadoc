import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_activity_stat.dart';
import 'package:nubia_domain/src/entities/cabinet_billing_stats.dart';

abstract class CabinetStatsRepository {
  /// GET /v1/cabinet/stats/activity (#4153).
  Future<Either<Failure, List<CabinetActivityStat>>> getActivityStats();

  /// GET /v1/cabinet/stats/billing (#4153).
  Future<Either<Failure, CabinetBillingStats>> getBillingStats();
}
