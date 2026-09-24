import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/cabinet_patients/cabinet_patients_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #7535 : la liste patients secrétariat était figée aux 50
  // premiers dossiers — l'API pagine par `cursor`, le client envoyait un
  // paramètre `page` que le serveur ignorait silencieusement. Le client doit
  // suivre `page.next_cursor` jusqu'à épuisement, comme
  // NotificationApi.getNotifications() (#6633).
  group('CabinetPatientsApi.list', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    Map<String, dynamic> patientJson(String id) => {
          'id': id,
          'first_name': 'Prénom$id',
          'last_name': 'Nom$id',
          'created_at': '2026-09-05T12:22:10.033126+00:00',
          'contact': <String, dynamic>{},
        };

    test('suit page.next_cursor jusqu\'à épuisement et concatène toutes les pages',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [patientJson('p1')],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 200, 'offset': 0},
        }),
      );

      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [patientJson('p2')],
          'page': {'next_cursor': null, 'limit': 200, 'offset': 0},
        }),
      );

      final patients = await CabinetPatientsApi(apiClient).list();

      expect(patients.length, 2,
          reason: 'les 2 pages doivent être concaténées');
      expect(patients.map((p) => p.id), containsAll(['p1', 'p2']));

      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200},
        ),
      ).called(1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [patientJson('p1')],
          'page': {'next_cursor': null, 'limit': 200, 'offset': 0},
        }),
      );

      final patients = await CabinetPatientsApi(apiClient).list();

      expect(patients.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200},
        ),
      ).called(1);
    });

    test('q ajoute le paramètre de recherche à chaque page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200, 'q': 'QAR69'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [patientJson('p1')],
          'page': {'next_cursor': null, 'limit': 200, 'offset': 0},
        }),
      );

      final patients = await CabinetPatientsApi(apiClient).list(q: 'QAR69');

      expect(patients.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients',
          queryParameters: {'limit': 200, 'q': 'QAR69'},
        ),
      ).called(1);
    });
  });

  // Régression #7560 : `GET /v1/cabinet/patients/:id/notes` n'était appelé
  // nulle part côté front — les notes écrites étaient donc invisibles à la
  // réouverture de la fiche.
  group('CabinetPatientsApi.listNotes', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    Map<String, dynamic> noteJson(String id) => {
          'note_id': id,
          'note_kind': 'observation',
          'text': 'Note $id',
          'author_id': 'user-1',
          'created_at': '2026-09-24T07:55:29+00:00',
        };

    test('suit page.next_cursor jusqu\'à épuisement et concatène toutes les pages',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients/pat-1/notes',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [noteJson('n1')],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 100, 'offset': 0},
        }),
      );

      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients/pat-1/notes',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [noteJson('n2')],
          'page': {'next_cursor': null, 'limit': 100, 'offset': 0},
        }),
      );

      final notes = await CabinetPatientsApi(apiClient).listNotes('pat-1');

      expect(notes.length, 2, reason: 'les 2 pages doivent être concaténées');
      expect(notes.map((n) => n.id), containsAll(['n1', 'n2']));
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients/pat-1/notes',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [noteJson('n1')],
          'page': {'next_cursor': null, 'limit': 100, 'offset': 0},
        }),
      );

      final notes = await CabinetPatientsApi(apiClient).listNotes('pat-1');

      expect(notes.length, 1);
      expect(notes.first.text, 'Note n1');
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/patients/pat-1/notes',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });
  });
}
