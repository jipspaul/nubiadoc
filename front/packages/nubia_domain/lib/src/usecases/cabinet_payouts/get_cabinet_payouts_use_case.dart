import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_payout.dart';
import 'package:nubia_domain/src/repositories/cabinet_payouts_repository.dart';

class GetCabinetPayoutsUseCase {
  final CabinetPayoutsRepository _repository;

  const GetCabinetPayoutsUseCase(this._repository);

  Future<Either<Failure, List<CabinetPayout>>> call() =>
      _repository.getPayouts();
}
