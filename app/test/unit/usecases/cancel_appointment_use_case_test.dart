import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';
import 'package:nubia_patient/domain/usecases/appointments/cancel_appointment_use_case.dart';

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

Appointment _makeAppointment({
  required DateTime startsAt,
  String id = 'appt1',
}) =>
    Appointment(
      id: id,
      cabinetId: 'cab1',
      practitionerName: 'Dr. Marin',
      practitionerSpecialty: 'Dentiste',
      startsAt: startsAt,
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

void main() {
  late MockAppointmentRepository repository;
  late CancelAppointmentUseCase useCase;

  setUp(() {
    repository = MockAppointmentRepository();
    useCase = CancelAppointmentUseCase(repository);
  });

  test('cancels successfully when appointment is more than 24 h away', () async {
    final appt = _makeAppointment(
      startsAt: DateTime.now().add(const Duration(hours: 25)),
    );
    final cancelled = _makeAppointment(
      startsAt: appt.startsAt,
      id: appt.id,
    );
    when(() => repository.cancel(appt.id))
        .thenAnswer((_) async => Right(cancelled));

    final result = await useCase(appt);

    expect(result.isRight(), isTrue);
    verify(() => repository.cancel(appt.id)).called(1);
  });

  test('returns ValidationFailure when appointment starts in less than 24 h', () async {
    final appt = _makeAppointment(
      startsAt: DateTime.now().add(const Duration(hours: 10)),
    );

    final result = await useCase(appt);

    expect(result.isLeft(), isTrue);
    result.fold(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected failure'),
    );
    verifyNever(() => repository.cancel(any()));
  });
}
