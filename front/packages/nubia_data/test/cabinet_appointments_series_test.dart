// #4088 : POST /v1/cabinet/appointments/series — vérifie le mapping des
// erreurs métier (404/409/422) en Failure typées côté repository, même
// pattern que cabinet_appointments_confirm_test.dart (#4535).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/appointment_series_dto.dart';
import 'package:nubia_data/src/remote/cabinet_appointments/cabinet_appointments_api.dart';
import 'package:nubia_data/src/repositories/cabinet_appointments_repository_impl.dart';
import 'package:nubia_domain/src/entities/appointment_series.dart';
import 'package:nubia_domain/src/error/failure.dart';

class MockCabinetAppointmentsApi extends Mock
    implements CabinetAppointmentsApi {}

void main() {
  late MockCabinetAppointmentsApi api;
  late CabinetAppointmentsRepositoryImpl repository;

  final occurrences = [
    AppointmentSeriesOccurrence(
      startsAt: DateTime(2026, 7, 1, 9, 0),
      endsAt: DateTime(2026, 7, 1, 9, 30),
    ),
  ];

  setUp(() {
    api = MockCabinetAppointmentsApi();
    repository = CabinetAppointmentsRepositoryImpl(api);
  });

  test('createSeries() sur 201 renvoie la série créée', () async {
    when(() => api.createSeries(
          practitionerId: any(named: 'practitionerId'),
          patientId: any(named: 'patientId'),
          motif: any(named: 'motif'),
          occurrences: any(named: 'occurrences'),
        )).thenAnswer((_) async => const AppointmentSeriesDto(
          recurrenceId: 'rec-1',
          appointments: [
            AppointmentSeriesItemDto(
              id: 'app-1',
              recurrenceIndex: 1,
              startsAt: '2026-07-01T09:00:00Z',
              endsAt: '2026-07-01T09:30:00Z',
            ),
          ],
        ));

    final result = await repository.createSeries(
      practitionerId: 'prac-1',
      patientId: 'pat-1',
      motif: 'Parodontologie',
      occurrences: occurrences,
    );

    expect(result.isRight(), isTrue);
    result.fold(
      (_) => fail('devrait être un Right'),
      (series) {
        expect(series.recurrenceId, 'rec-1');
        expect(series.appointments, hasLength(1));
        expect(series.appointments.single.recurrenceIndex, 1);
      },
    );
  });

  test('createSeries() sur 409 renvoie ServerFailure (slot_taken)', () async {
    when(() => api.createSeries(
          practitionerId: any(named: 'practitionerId'),
          patientId: any(named: 'patientId'),
          motif: any(named: 'motif'),
          occurrences: any(named: 'occurrences'),
        )).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/cabinet/appointments/series'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/cabinet/appointments/series'),
          statusCode: 409,
        ),
      ),
    );

    final result = await repository.createSeries(
      practitionerId: 'prac-1',
      patientId: 'pat-1',
      motif: 'Parodontologie',
      occurrences: occurrences,
    );

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<ServerFailure>()),
      (_) => fail('devrait être un Left'),
    );
  });

  test('createSeries() sur 404 renvoie NotFoundFailure', () async {
    when(() => api.createSeries(
          practitionerId: any(named: 'practitionerId'),
          patientId: any(named: 'patientId'),
          motif: any(named: 'motif'),
          occurrences: any(named: 'occurrences'),
        )).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/cabinet/appointments/series'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/cabinet/appointments/series'),
          statusCode: 404,
        ),
      ),
    );

    final result = await repository.createSeries(
      practitionerId: 'prac-1',
      patientId: 'pat-unknown',
      motif: 'Parodontologie',
      occurrences: occurrences,
    );

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<NotFoundFailure>()),
      (_) => fail('devrait être un Left'),
    );
  });

  test('createSeries() sur 422 renvoie ValidationFailure', () async {
    when(() => api.createSeries(
          practitionerId: any(named: 'practitionerId'),
          patientId: any(named: 'patientId'),
          motif: any(named: 'motif'),
          occurrences: any(named: 'occurrences'),
        )).thenThrow(
      DioException(
        requestOptions: RequestOptions(path: '/cabinet/appointments/series'),
        response: Response(
          requestOptions:
              RequestOptions(path: '/cabinet/appointments/series'),
          statusCode: 422,
        ),
      ),
    );

    final result = await repository.createSeries(
      practitionerId: 'prac-1',
      patientId: 'pat-1',
      motif: 'Parodontologie',
      occurrences: const [],
    );

    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<ValidationFailure>()),
      (_) => fail('devrait être un Left'),
    );
  });
}
