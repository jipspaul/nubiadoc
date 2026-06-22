import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/agenda_entry.dart';
import 'package:nubia_domain/src/repositories/cabinet_agenda_repository.dart';

class GetCabinetAgendaUseCase {
  final CabinetAgendaRepository _repository;

  const GetCabinetAgendaUseCase(this._repository);

  Future<Either<Failure, List<AgendaEntry>>> call(
    DateTime weekStart, {
    bool includePast = false,
  }) {
    if (includePast) return _repository.list();
    final weekEnd = weekStart.add(const Duration(days: 7));
    return _repository.list(from: weekStart, to: weekEnd);
  }
}
