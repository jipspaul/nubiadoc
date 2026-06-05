import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

@injectable
class BookAppointmentUseCase {
  final AppointmentRepository _repository;

  const BookAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call({
    required String slotId,
    required String motif,
  }) =>
      _repository.book(slotId: slotId, motif: motif);
}
