import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/appointment_series.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/cabinet_appointments_repository.dart';

class CreateAppointmentSeriesUseCase {
  final CabinetAppointmentsRepository _repository;

  const CreateAppointmentSeriesUseCase(this._repository);

  Future<Either<Failure, CreatedAppointmentSeries>> call({
    required String practitionerId,
    required String patientId,
    String? motif,
    required List<AppointmentSeriesOccurrence> occurrences,
  }) =>
      _repository.createSeries(
        practitionerId: practitionerId,
        patientId: patientId,
        motif: motif,
        occurrences: occurrences,
      );
}
