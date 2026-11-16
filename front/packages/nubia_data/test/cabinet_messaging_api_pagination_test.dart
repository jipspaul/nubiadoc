import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/cabinet_messaging/cabinet_messaging_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #8608 : même défaut que #3848 (MessagingApi), mais sur le
  // client partagé cabinet/pharmacie. GET $basePath/conversations/:id/messages
  // pagine en avant (created_at ASC) — la 1re page ne renvoie que les
  // messages les plus ANCIENS. getMessages() ignorait `page.next_cursor` : un
  // fil de plus de 20 messages laissait le message que le patient vient
  // d'écrire invisible côté secrétariat/praticien/pharmacie. Le client doit
  // suivre next_cursor jusqu'à épuisement.
  group('CabinetMessagingApi.getMessages', () {
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
          '/cabinet/conversations/conv-1/messages',
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
          '/cabinet/conversations/conv-1/messages',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'm2',
              'body': 'QA R178 — message de test patient',
              'sender': 'patient',
              'created_at': '2026-11-16T01:10:48Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final messages = await CabinetMessagingApi(apiClient).getMessages(
        'conv-1',
      );

      expect(messages.length, 2,
          reason: 'les 2 pages doivent être concaténées');
      expect(messages.last.text, 'QA R178 — message de test patient',
          reason: 'le message le plus récent (2e page) doit être présent');

      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations/conv-1/messages',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations/conv-1/messages',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations/conv-2/messages',
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

      final messages = await CabinetMessagingApi(apiClient).getMessages(
        'conv-2',
      );

      expect(messages.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/cabinet/conversations/conv-2/messages',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });

    test('respecte le basePath /pharmacy pour l\'app pharmacie', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/pharmacy/conversations/conv-3/messages',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'm1',
              'body': 'QA-R176-B9-PHARMA-1793667327',
              'sender': 'patient',
              'created_at': '2026-11-03T00:55:32Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final messages = await CabinetMessagingApi(
        apiClient,
        basePath: '/pharmacy',
      ).getMessages('conv-3');

      expect(messages.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/pharmacy/conversations/conv-3/messages',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });
  });
}
