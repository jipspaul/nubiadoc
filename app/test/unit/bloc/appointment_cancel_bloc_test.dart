import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/cancel_appointment_use_case.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_cancel_bloc.dart';

class MockCancelAppointmentUseCase extends Mock
    implements CancelAppointmentUseCase {}

Appointment _makeAppointment({required DateTime startsAt}) => Appointment(
      id: 'appt-1',
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Marin',
      practitionerSpecialty: 'Dentiste',
      startsAt: startsAt,
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

void main() {
  late MockCancelAppointmentUseCase useCase;

  setUp(() {
    useCase = MockCancelAppointmentUseCase();
  });

  final farAppointment = _makeAppointment(
    startsAt: DateTime.now().add(const Duration(hours: 48)),
  );
  final cancelled = farAppointment;

  blocTest<AppointmentCancelBloc, AppointmentCancelState>(
    'émet [InProgress, Success] quand l\'annulation réussit',
    build: () {
      when(() => useCase(farAppointment))
          .thenAnswer((_) async => Right(cancelled));
      return AppointmentCancelBloc(useCase);
    },
    act: (bloc) => bloc.add(AppointmentCancelRequested(
      appointment: farAppointment,
      reason: 'Empêchement',
    )),
    expect: () => [
      const AppointmentCancelInProgress(),
      AppointmentCancelSuccess(cancelled),
    ],
  );

  blocTest<AppointmentCancelBloc, AppointmentCancelState>(
    'émet [InProgress, Failure] quand le use case retourne une ValidationFailure',
    build: () {
      when(() => useCase(farAppointment)).thenAnswer(
        (_) async => const Left(
          ValidationFailure(
            message:
                'Annulation impossible : le rendez-vous commence dans moins de 24 h.',
          ),
        ),
      );
      return AppointmentCancelBloc(useCase);
    },
    act: (bloc) => bloc.add(AppointmentCancelRequested(
      appointment: farAppointment,
      reason: '',
    )),
    expect: () => [
      const AppointmentCancelInProgress(),
      const AppointmentCancelFailure(
        'Annulation impossible : le rendez-vous commence dans moins de 24 h.',
      ),
    ],
  );
}
