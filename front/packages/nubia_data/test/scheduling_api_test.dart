// Régression #4543 — POST /appointments/:id/cancel répond
// `{appointment_id, status}` (api/src/appointments.rs::CancelResponse), pas
// un appointment complet. Décoder cette réponse directement en AppointmentDto
// levait une exception ('starts_at' absent) même quand l'annulation avait
// réussi côté serveur (200), masquant le succès derrière une "erreur de
// décodage" et laissant le RDV affiché comme actif. Même défaut pour
// checkin() (CheckinResponse tout aussi minimal).
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/scheduling/scheduling_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockApiClient apiClient;
  late MockDio dio;
  late SchedulingApi api;

  setUp(() {
    apiClient = MockApiClient();
    dio = MockDio();
    when(() => apiClient.dio).thenReturn(dio);
    api = SchedulingApi(apiClient);
  });

  Response<T> fakeResponse<T>(T? data) =>
      Response<T>(data: data, requestOptions: RequestOptions(path: ''));

  final fullAppointment = {
    'id': 'appt-1',
    'cabinet_id': 'cab-1',
    'practitioner_name': 'Dr Test',
    'practitioner_specialty': 'Dentiste',
    'starts_at': '2026-08-10T09:00:00Z',
    'duration_minutes': 30,
    'motif': 'Contrôle',
    'status': 'cancelled',
    'type': 'in_person',
  };

  group('SchedulingApi.cancel (#4543)', () {
    test(
        'décode la réponse minimale du POST cancel sans lever, puis '
        're-fetch l\'appointment à jour via GET /appointments/:id', () async {
      when(() => dio.post<void>('/appointments/appt-1/cancel'))
          .thenAnswer((_) async => fakeResponse<void>(null));
      when(() => dio.get<Map<String, dynamic>>('/appointments/appt-1'))
          .thenAnswer((_) async => fakeResponse(fullAppointment));

      final dto = await api.cancel('appt-1');

      expect(dto.id, 'appt-1');
      expect(dto.status, 'cancelled');
      verify(() => dio.post<void>('/appointments/appt-1/cancel')).called(1);
      verify(() => dio.get<Map<String, dynamic>>('/appointments/appt-1'))
          .called(1);
    });
  });

  group('SchedulingApi.checkin (#4543)', () {
    test(
        'décode la réponse minimale du POST checkin sans lever, puis '
        're-fetch l\'appointment à jour via GET /appointments/:id', () async {
      when(() => dio.post<void>('/appointments/appt-1/checkin'))
          .thenAnswer((_) async => fakeResponse<void>(null));
      when(() => dio.get<Map<String, dynamic>>('/appointments/appt-1'))
          .thenAnswer((_) async => fakeResponse({
                ...fullAppointment,
                'status': 'checked_in',
              }));

      final dto = await api.checkin('appt-1');

      expect(dto.status, 'checked_in');
      verify(() => dio.post<void>('/appointments/appt-1/checkin')).called(1);
    });
  });

  group('PreparationDto.fromJson (#6203)', () {
    test(
        'décode provider.name, establishment.access (door_code/parking/pmr) '
        'et reminder_at — jetés jusque-là par le DTO', () {
      final dto = PreparationDto.fromJson({
        'provider': {'name': 'Dr Claire Lefèvre'},
        'establishment': {
          'address': '12 rue de la République, 69002 Lyon',
          'geo': {'lat': 45.7602, 'lon': 4.8322},
          'access': {'door_code': null, 'parking': true, 'pmr': true},
        },
        'bring': [
          {'label': 'Carte Vitale', 'required': true},
          {'label': 'Carte mutuelle', 'required': true},
        ],
        'reminder_at': '2026-09-02T07:00:00+00:00',
      });

      expect(dto.providerName, 'Dr Claire Lefèvre');
      expect(dto.address, '12 rue de la République, 69002 Lyon');
      expect(dto.access?.doorCode, isNull);
      expect(dto.access?.parking, isTrue);
      expect(dto.access?.pmr, isTrue);
      expect(dto.reminderAt, DateTime.parse('2026-09-02T07:00:00+00:00'));
    });
  });
}
