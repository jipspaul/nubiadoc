import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_payout.dart';

abstract class CabinetPayoutsRepository {
  /// GET /v1/cabinet/payouts (#4129).
  Future<Either<Failure, List<CabinetPayout>>> getPayouts();

  /// POST /v1/cabinet/payouts/:id/reconcile (#5969) — persiste le
  /// rapprochement manuel côté back, survit à un refresh.
  Future<Either<Failure, Unit>> markReconciled(String id);

  /// POST /v1/cabinet/payouts/:id/flag-accountant (#5969) — trace le
  /// signalement au comptable côté back.
  Future<Either<Failure, Unit>> flagToAccountant(String id);
}
