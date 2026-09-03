import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/billing/billing_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #6288 : la tuile "Mes devis & paiements" du profil patient
  // affichait "6 à signer" au lieu de 58 — getQuotes() n'appelait ni `limit`
  // ni `page.next_cursor` et le compteur ne portait donc que sur la 1re page
  // de 20 devis renvoyée par l'API. Le client doit suivre next_cursor
  // jusqu'à épuisement, comme SchedulingApi.getHistory().
  group('BillingApi.getQuotes', () {
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
          '/billing/quotes',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'q1',
              'status': 'sent',
              'total_amount_cents': 10000,
              'created_at': '2026-07-02T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 100},
        }),
      );

      when(
        () => dio.get<Map<String, dynamic>>(
          '/billing/quotes',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'q2',
              'status': 'sent',
              'total_amount_cents': 20000,
              'created_at': '2026-07-14T06:59:08Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final quotes = await BillingApi(apiClient).getQuotes();

      expect(quotes.length, 2, reason: 'les 2 pages doivent être concaténées');
      expect(quotes.map((q) => q.id), containsAll(['q1', 'q2']));

      verify(
        () => dio.get<Map<String, dynamic>>(
          '/billing/quotes',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/billing/quotes',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/billing/quotes',
          queryParameters: {'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'q1',
              'status': 'signed',
              'total_amount_cents': 10000,
              'created_at': '2026-07-02T09:45:54Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final quotes = await BillingApi(apiClient).getQuotes();

      expect(quotes.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/billing/quotes',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });
  });
}
