import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/repositories/slots_repository.dart';

class ListBookableSlotsUseCase {
  final SlotsRepository _repository;

  const ListBookableSlotsUseCase(this._repository);

  Future<Either<Failure, List<Slot>>> call({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  }) =>
      _repository.list(
        from: from,
        to: to,
        practitionerId: practitionerId,
      );
}
