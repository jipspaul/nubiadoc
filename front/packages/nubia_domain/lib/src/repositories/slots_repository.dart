import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/slot.dart';

abstract class SlotsRepository {
  Future<Either<Failure, List<Slot>>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  });
  Future<Either<Failure, Slot>> getById(String id);
  Future<Either<Failure, Slot>> create(Slot slot);
  Future<Either<Failure, Slot>> update(Slot slot);
}
