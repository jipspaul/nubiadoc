import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';

/// Cancellation deadline: 24 h before the appointment.
const Duration _cancelDeadline = Duration(hours: 24);

@injectable
class CancelAppointmentUseCase {
  final AppointmentRepository _repository;

  const CancelAppointmentUseCase(this._repository);

  /// Returns [ValidationFailure] when the appointment starts in less than
  /// [_cancelDeadline] (too late to cancel without penalty).
  Future<Either<Failure, Appointment>> call(Appointment appointment) async {
    final timeLeft = appointment.startsAt.difference(DateTime.now());
    if (timeLeft < _cancelDeadline) {
      return const Left(ValidationFailure(
        message:
            'Annulation impossible : le rendez-vous commence dans moins de 24 h.',
      ));
    }
    return _repository.cancel(appointment.id);
  }
}
