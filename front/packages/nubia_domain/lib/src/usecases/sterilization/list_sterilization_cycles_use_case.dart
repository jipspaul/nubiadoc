import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/sterilization_cycle.dart';
import 'package:nubia_domain/src/repositories/sterilization_repository.dart';

class ListSterilizationCyclesUseCase {
  final SterilizationRepository _repository;

  const ListSterilizationCyclesUseCase(this._repository);

  Future<Either<Failure, List<SterilizationCycle>>> call() =>
      _repository.listCycles();
}
