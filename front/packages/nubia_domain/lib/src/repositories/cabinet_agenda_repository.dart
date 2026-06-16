import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';

abstract class CabinetAgendaRepository {
  Future<Either<Failure, List<AgendaEntry>>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  });
  Future<Either<Failure, AgendaEntry>> getById(String id);
  Future<Either<Failure, AgendaEntry>> create(AgendaEntry entry);
  Future<Either<Failure, AgendaEntry>> update(AgendaEntry entry);
}
