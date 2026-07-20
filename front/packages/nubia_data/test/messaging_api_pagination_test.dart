import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/messaging/messaging_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #3848 : GET /v1/conversations/:id/messages pagine en avant
  // (created_at ASC) — la 1re page ne renvoie que les messages les plus
  // ANCIENS. getMessages() ignorait totalement `page.next_cursor` : un fil
  // de plus de 20 messages laissait les réponses récentes du praticien et
  // les envois du patient invisibles. Le client doit suivre next_cursor
  // jusqu'à épuisement.
  group('MessagingApi.getMessages', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('suit next_cursor jusqu\'à épuisement et concatène toutes les pages',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'm1',
              'body': 'ancien',
              'sender': 'patient',
              'created_at': '2026-07-02T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 100},
        }),
      );

      when(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'm2',
              'body': 'recent - reponse praticien',
              'sender': 'cabinet',
              'created_at': '2026-07-14T06:59:08Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final messages = await MessagingApi(apiClient).getMessages('conv-1');

      expect(messages.length, 2,
          reason: 'les 2 pages doivent être concaténées');
      expect(messages.last.text, 'recent - reponse praticien',
          reason: 'le message le plus récent (2e page) doit être présent');

      // 1er appel sans cursor, 2e appel avec le cursor de la page précédente.
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-1/messages',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-2/messages',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'm1',
              'body': 'seul message',
              'sender': 'patient',
              'created_at': '2026-07-02T09:45:54Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      // Si le code appelait dio.get une 2e fois avec des queryParameters non
      // stubbés, mocktail lèverait une MissingStubError ici (aucun 2e stub
      // enregistré) : ce test échouerait à l'exécution plutôt que de passer
      // silencieusement.
      final messages = await MessagingApi(apiClient).getMessages('conv-2');

      expect(messages.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/conversations/conv-2/messages',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });
  });
}
