import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/waiting_room_entry.dart';
import 'package:nubia_domain/src/entities/waiting_list_entry.dart';

abstract class WaitingRoomRepository {
  Future<Either<Failure, List<WaitingRoomEntry>>> list();
  Future<Either<Failure, WaitingRoomEntry>> getById(String id);
  Future<Either<Failure, WaitingRoomEntry>> create(WaitingRoomEntry entry);
  Future<Either<Failure, WaitingRoomEntry>> update(WaitingRoomEntry entry);
  Future<Either<Failure, WaitingRoomEntry>> callNext();
}

abstract class WaitingListRepository {
  Future<Either<Failure, List<WaitingListEntry>>> list();
  Future<Either<Failure, WaitingListEntry>> getById(String id);
  Future<Either<Failure, WaitingListEntry>> create(WaitingListEntry entry);
  Future<Either<Failure, WaitingListEntry>> update(WaitingListEntry entry);
  Future<Either<Failure, Unit>> offerSlot(String id);
}
