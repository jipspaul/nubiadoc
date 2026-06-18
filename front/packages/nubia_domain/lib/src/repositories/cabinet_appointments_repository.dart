import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_appointment.dart';

abstract class CabinetAppointmentsRepository {
  Future<Either<Failure, List<CabinetAppointment>>> list({int page = 1});
  Future<Either<Failure, CabinetAppointment>> getById(String id);
  Future<Either<Failure, CabinetAppointment>> create(CabinetAppointment appointment);
  Future<Either<Failure, CabinetAppointment>> update(CabinetAppointment appointment);
  Future<Either<Failure, CabinetAppointment>> confirm(String id);
}
