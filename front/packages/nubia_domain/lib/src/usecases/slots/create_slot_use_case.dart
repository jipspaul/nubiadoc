import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/slot.dart';
import 'package:nubia_domain/src/repositories/slots_repository.dart';

class CreateSlotUseCase {
  final SlotsRepository _repository;

  const CreateSlotUseCase(this._repository);

  Future<Either<Failure, Slot>> call({
    required String cabinetId,
    required String practitionerId,
    required DateTime start,
    required Duration duration,
  }) {
    final slot = Slot(
      id: '',
      cabinetId: cabinetId,
      practitionerId: practitionerId,
      startsAt: start,
      endsAt: start.add(duration),
      isAvailable: true,
    );
    return _repository.create(slot);
  }
}
