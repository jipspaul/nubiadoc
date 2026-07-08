import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_practitioner.dart';
import 'package:nubia_domain/src/repositories/cabinet_agenda_repository.dart';

/// Liste les praticiens (roster) du cabinet — source de vérité pour rattacher
/// un créneau ou un RDV au bon médecin (secrétariat). `cabinet_id` scopé JWT.
class ListCabinetPractitionersUseCase {
  final CabinetAgendaRepository _repository;

  const ListCabinetPractitionersUseCase(this._repository);

  Future<Either<Failure, List<CabinetPractitioner>>> call() =>
      _repository.listPractitioners();
}
