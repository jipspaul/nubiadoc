import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment_motif.dart';

abstract class AppointmentMotifsRepository {
  Future<Either<Failure, List<AppointmentMotif>>> list();

  Future<Either<Failure, AppointmentMotif>> create({
    required String label,
    int? defaultDurationMinutes,
  });

  Future<Either<Failure, AppointmentMotif>> update(
    String id, {
    String? label,
    int? defaultDurationMinutes,
  });

  Future<Either<Failure, void>> delete(String id);
}
