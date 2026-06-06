import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/appointment.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_appointment_history_use_case.dart';
import 'package:nubia_patient/domain/usecases/appointments/get_upcoming_appointments_use_case.dart';
import 'package:nubia_patient/presentation/features/appointments/bloc/appointment_bloc.dart';

class MockGetUpcomingAppointmentsUseCase extends Mock
    implements GetUpcomingAppointmentsUseCase {}

class MockGetAppointmentHistoryUseCase extends Mock
    implements GetAppointmentHistoryUseCase {}

Appointment _makeAppointment(String id) => Appointment(
      id: id,
      cabinetId: 'cab-1',
      practitionerName: 'Dr. Martin',
      practitionerSpecialty: 'Dentiste',
      startsAt: DateTime.now().add(const Duration(days: 7)),
      duration: const Duration(minutes: 30),
      motif: 'Contrôle',
      status: AppointmentStatus.confirmed,
    );

void main() {
  late MockGetUpcomingAppointmentsUseCase getUpcoming;
  late MockGetAppointmentHistoryUseCase getHistory;

  setUp(() {
    getUpcoming = MockGetUpcomingAppointmentsUseCase();
    getHistory = MockGetAppointmentHistoryUseCase();
  });

  blocTest<AppointmentBloc, AppointmentState>(
    'émet [Loading, Loaded] quand les deux use cases réussissent',
    build: () {
      final upcoming = [_makeAppointment('u1')];
      final history = [_makeAppointment('h1'), _makeAppointment('h2')];
      when(() => getUpcoming()).thenAnswer((_) async => Right(upcoming));
      when(() => getHistory()).thenAnswer((_) async => Right(history));
      return AppointmentBloc(getUpcoming, getHistory);
    },
    act: (bloc) => bloc.add(const AppointmentLoadRequested()),
    expect: () => [
      const AppointmentLoading(),
      isA<AppointmentLoaded>()
          .having((s) => s.upcoming.length, 'upcoming count', 1)
          .having((s) => s.history.length, 'history count', 2),
    ],
  );

  blocTest<AppointmentBloc, AppointmentState>(
    'émet [Loading, Error] quand getUpcoming échoue',
    build: () {
      when(() => getUpcoming()).thenAnswer(
        (_) async => const Left(NetworkFailure()),
      );
      return AppointmentBloc(getUpcoming, getHistory);
    },
    act: (bloc) => bloc.add(const AppointmentLoadRequested()),
    expect: () => [
      const AppointmentLoading(),
      const AppointmentError('Erreur réseau. Vérifiez votre connexion.'),
    ],
  );

  blocTest<AppointmentBloc, AppointmentState>(
    'émet [Loading, Error] quand getHistory échoue',
    build: () {
      when(() => getUpcoming())
          .thenAnswer((_) async => Right([_makeAppointment('u1')]));
      when(() => getHistory()).thenAnswer(
        (_) async => const Left(ServerFailure(message: 'Erreur serveur.')),
      );
      return AppointmentBloc(getUpcoming, getHistory);
    },
    act: (bloc) => bloc.add(const AppointmentLoadRequested()),
    expect: () => [
      const AppointmentLoading(),
      const AppointmentError('Erreur serveur.'),
    ],
  );
}
