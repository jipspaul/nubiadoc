import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment_motif.dart';
import 'package:nubia_domain/src/repositories/appointment_motifs_repository.dart';

class ListAppointmentMotifsUseCase {
  final AppointmentMotifsRepository _repository;

  const ListAppointmentMotifsUseCase(this._repository);

  Future<Either<Failure, List<AppointmentMotif>>> call() => _repository.list();
}
