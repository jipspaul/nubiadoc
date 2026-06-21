import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/waiting_room_entry.dart';
import 'package:nubia_domain/src/repositories/waiting_repository.dart';

class CallNextUseCase {
  final WaitingRoomRepository _repository;

  const CallNextUseCase(this._repository);

  Future<Either<Failure, WaitingRoomEntry>> call() => _repository.callNext();
}
