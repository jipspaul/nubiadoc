import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/waiting_repository.dart';

class NotifyWaitingRoomPractitionerUseCase {
  final WaitingRoomRepository _repository;

  const NotifyWaitingRoomPractitionerUseCase(this._repository);

  Future<Either<Failure, Unit>> call(String id) =>
      _repository.notifyPractitioner(id);
}
