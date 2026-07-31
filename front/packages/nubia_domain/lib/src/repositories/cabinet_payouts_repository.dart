import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_payout.dart';

abstract class CabinetPayoutsRepository {
  /// GET /v1/cabinet/payouts (#4129).
  Future<Either<Failure, List<CabinetPayout>>> getPayouts();
}
