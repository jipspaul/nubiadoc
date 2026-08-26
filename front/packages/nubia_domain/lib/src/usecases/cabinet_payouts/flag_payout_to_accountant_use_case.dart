import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_payouts_repository.dart';

/// Signale l'écart au comptable (#5969) : trace réellement l'action côté
/// back, remplace l'ancien handler no-op qui ne faisait rien.
class FlagPayoutToAccountantUseCase {
  final CabinetPayoutsRepository _repository;

  const FlagPayoutToAccountantUseCase(this._repository);

  Future<Either<Failure, Unit>> call(String id) =>
      _repository.flagToAccountant(id);
}
