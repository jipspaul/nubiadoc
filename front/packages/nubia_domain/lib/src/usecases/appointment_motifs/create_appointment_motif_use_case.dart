import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment_motif.dart';
import 'package:nubia_domain/src/repositories/appointment_motifs_repository.dart';

class CreateAppointmentMotifUseCase {
  final AppointmentMotifsRepository _repository;

  const CreateAppointmentMotifUseCase(this._repository);

  Future<Either<Failure, AppointmentMotif>> call({
    required String label,
    int? defaultDurationMinutes,
  }) =>
      _repository.create(
        label: label,
        defaultDurationMinutes: defaultDurationMinutes,
      );
}
