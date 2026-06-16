import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';

abstract class CabinetPatientsRepository {
  Future<Either<Failure, List<CabinetPatient>>> list({int page = 1});
  Future<Either<Failure, CabinetPatient>> getById(String id);
  Future<Either<Failure, CabinetPatient>> create(CabinetPatient patient);
  Future<Either<Failure, CabinetPatient>> update(CabinetPatient patient);
}
