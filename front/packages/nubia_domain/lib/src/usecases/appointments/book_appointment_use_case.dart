import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/appointment.dart';
import 'package:nubia_domain/src/repositories/appointment_repository.dart';

class BookAppointmentUseCase {
  final AppointmentRepository _repository;

  const BookAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call({
    required String slotId,
    required String motif,
  }) =>
      _repository.book(slotId: slotId, motif: motif);
}
