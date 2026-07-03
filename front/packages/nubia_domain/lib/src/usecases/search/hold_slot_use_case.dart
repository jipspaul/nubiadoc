import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/search_repository.dart';

class HoldSlotUseCase {
  final SearchRepository _repository;

  const HoldSlotUseCase(this._repository);

  Future<Either<Failure, String>> call(String slotId) =>
      _repository.holdSlot(slotId);
}
