import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/pharmacy_quotes/pharmacy_quotes_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #8633 : `GET /v1/pharmacy/quotes` était figé à `LIMIT 200`
  // sans aucun paramètre, et l'écran présentait ce plafond comme un total
  // (« 200 devis affichés sur 200 »). Le serveur accepte maintenant
  // `?limit=`/`?cursor=` et renvoie `page.next_cursor` (même pattern que
  // `pharmacy::orders::list_pharmacy_orders`) ; le client doit le suivre
  // jusqu'à épuisement, comme PharmacyOrdersApi.list().
  late MockApiClient apiClient;
  late MockDio dio;

  setUp(() {
    apiClient = MockApiClient();
    dio = MockDio();
    when(() => apiClient.dio).thenReturn(dio);
  });

  Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
      Response(data: data, requestOptions: RequestOptions(path: ''));

  group('PharmacyQuotesApi.list (espace pharmacie)', () {
    test('suit next_cursor jusqu\'à épuisement et concatène toutes les pages',
        () async {
      when(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'quote1',
              'pharmacy_id': 'pharm1',
              'items': <Map<String, dynamic>>[],
              'total_cents': 500,
              'status': 'draft',
              'created_at': '2026-08-19T08:00:00Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1'},
        }),
      );

      when(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{
            'limit': 500,
            'cursor': 'CURSOR_1',
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'quote2',
              'pharmacy_id': 'pharm1',
              'items': <Map<String, dynamic>>[],
              'total_cents': 700,
              'status': 'sent',
              'created_at': '2026-08-20T08:00:00Z',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final quotes = await PharmacyQuotesApi(apiClient).list();

      expect(quotes.length, 2, reason: 'les 2 pages doivent être concaténées');
      expect(quotes.map((q) => q.id), containsAll(['quote1', 'quote2']));

      verify(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).called(1);
      verify(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{
            'limit': 500,
            'cursor': 'CURSOR_1',
          },
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'quote1',
              'pharmacy_id': 'pharm1',
              'items': <Map<String, dynamic>>[],
              'total_cents': 500,
              'status': 'draft',
              'created_at': '2026-08-19T08:00:00Z',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final quotes = await PharmacyQuotesApi(apiClient).list();

      expect(quotes.length, 1);
      verify(
        () => dio.get<dynamic>(
          '/pharmacy/quotes',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).called(1);
    });
  });

  group('PharmacyQuotesApi.list (espace patient)', () {
    test('n\'envoie aucun paramètre de pagination (route sans cursor)',
        () async {
      when(
        () => dio.get<dynamic>(
          '/account/pharmacy-quotes',
          queryParameters: null,
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'quote1',
              'pharmacy_id': 'pharm1',
              'items': <Map<String, dynamic>>[],
              'total_cents': 500,
              'status': 'sent',
              'created_at': '2026-08-19T08:00:00Z',
            },
          ],
        }),
      );

      final quotes = await PharmacyQuotesApi(
        apiClient,
        space: PharmacyQuotesSpace.patient,
      ).list();

      expect(quotes.length, 1);
      verify(
        () => dio.get<dynamic>(
          '/account/pharmacy-quotes',
          queryParameters: null,
        ),
      ).called(1);
    });
  });
}
