import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/repositories/appointment_repository.dart';
import 'package:nubia_patient/domain/usecases/appointments/book_appointment_use_case.dart';

class MockAppointmentRepository extends Mock implements AppointmentRepository {}

Appointment _makeAppointment({String id = 'appt1'}) => Appointment(
      id: id,
      cabinetId: 'cab1',
      practitionerName: 'Dr. Marin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 3)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

void main() {
  late MockAppointmentRepository repository;
  late BookAppointmentUseCase useCase;

  setUp(() {
    repository = MockAppointmentRepository();
    useCase = BookAppointmentUseCase(repository);
  });

  test('returns Appointment on success', () async {
    final appt = _makeAppointment();
    when(() => repository.book(slotId: 'slot1', motif: 'Contrôle'))
        .thenAnswer((_) async => Right(appt));

    final result = await useCase(slotId: 'slot1', motif: 'Contrôle');

    expect(result, Right<Failure, Appointment>(appt));
    verify(() => repository.book(slotId: 'slot1', motif: 'Contrôle')).called(1);
  });

  test('returns ValidationFailure on double-booking', () async {
    when(() => repository.book(slotId: any(named: 'slotId'), motif: any(named: 'motif')))
        .thenAnswer((_) async => const Left(
              ValidationFailure(
                message: 'Vous avez déjà un rendez-vous sur ce créneau.',
              ),
            ));

    final result = await useCase(slotId: 'slot1', motif: 'Contrôle');

    expect(result.isLeft(), isTrue);
    result.fold(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected failure'),
    );
  });

  test('returns ValidationFailure when slot unavailable', () async {
    when(() => repository.book(slotId: any(named: 'slotId'), motif: any(named: 'motif')))
        .thenAnswer((_) async => const Left(
              ValidationFailure(
                message: "Ce créneau n'est plus disponible.",
              ),
            ));

    final result = await useCase(slotId: 'slot1', motif: 'Contrôle');

    expect(result.isLeft(), isTrue);
    result.fold(
      (f) => expect(f, isA<ValidationFailure>()),
      (_) => fail('expected failure'),
    );
  });
}
