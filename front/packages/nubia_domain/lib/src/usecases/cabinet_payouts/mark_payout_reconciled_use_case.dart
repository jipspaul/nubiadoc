import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_payouts_repository.dart';

/// Marque un virement comme rapproché (#5969) : persiste la décision
/// humaine côté back, contrairement à l'ancienne mutation Bloc locale
/// perdue au refresh.
class MarkPayoutReconciledUseCase {
  final CabinetPayoutsRepository _repository;

  const MarkPayoutReconciledUseCase(this._repository);

  Future<Either<Failure, Unit>> call(String id) =>
      _repository.markReconciled(id);
}
