import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/appointment_motifs_repository.dart';

class DeleteAppointmentMotifUseCase {
  final AppointmentMotifsRepository _repository;

  const DeleteAppointmentMotifUseCase(this._repository);

  Future<Either<Failure, void>> call(String id) => _repository.delete(id);
}
