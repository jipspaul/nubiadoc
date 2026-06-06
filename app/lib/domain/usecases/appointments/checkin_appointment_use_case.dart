import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

@injectable
class CheckinAppointmentUseCase {
  final AppointmentRepository _repository;

  const CheckinAppointmentUseCase(this._repository);

  Future<Either<Failure, Appointment>> call(String id) =>
      _repository.checkin(id);
}
