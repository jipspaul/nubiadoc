import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';

abstract class AppointmentRepository {
  Future<Either<Failure, List<Appointment>>> getUpcoming();
  Future<Either<Failure, List<Appointment>>> getHistory({int page = 1});
  Future<Either<Failure, Appointment>> getById(String id);
  Future<Either<Failure, Appointment>> book({
    required String slotId,
    required String motif,
  });
  Future<Either<Failure, Appointment>> cancel(String id);
  Future<Either<Failure, Appointment>> modify({
    required String id,
    required String newSlotId,
  });
}
