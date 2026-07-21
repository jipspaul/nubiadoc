import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment_motif.dart';
import 'package:nubia_domain/src/repositories/appointment_motifs_repository.dart';

class UpdateAppointmentMotifUseCase {
  final AppointmentMotifsRepository _repository;

  const UpdateAppointmentMotifUseCase(this._repository);

  Future<Either<Failure, AppointmentMotif>> call(
    String id, {
    String? label,
    int? defaultDurationMinutes,
  }) =>
      _repository.update(
        id,
        label: label,
        defaultDurationMinutes: defaultDurationMinutes,
      );
}
