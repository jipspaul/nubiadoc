import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';
import 'package:nubia_domain/src/entities/cabinet_practitioner.dart';

abstract class CabinetAgendaRepository {
  Future<Either<Failure, List<AgendaEntry>>> list({
    DateTime? from,
    DateTime? to,
    String? practitionerId,
  });

  /// Roster des praticiens du cabinet (source : `practitioners` de
  /// GET /v1/cabinet/agenda). Utilisé pour les sélecteurs de médecin.
  Future<Either<Failure, List<CabinetPractitioner>>> listPractitioners();

  Future<Either<Failure, AgendaEntry>> getById(String id);
  Future<Either<Failure, AgendaEntry>> create(AgendaEntry entry);
  Future<Either<Failure, AgendaEntry>> update(AgendaEntry entry);
}
