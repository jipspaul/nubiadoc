import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/cabinet_quotes/cabinet_quotes_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #7553 : la liste devis du cabinet entier était figée aux 200
  // premiers (défaut serveur `cabinet_quotes.rs`) — le client n'envoyait ni
  // `limit` ni `offset`. Sans appel explicite de pagination, le client doit
  // désormais paginer par `offset` jusqu'à une page non pleine, même pattern
  // que `ListPatientJournalUseCase._listAllCabinetQuotes` (#5572).
  group('CabinetQuotesApi.list', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<dynamic> fakeResponse(List<Map<String, dynamic>> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    Map<String, dynamic> quoteJson(String id) => {
          'id': id,
          'patient_id': 'p1',
          'patient_name': 'Patient Un',
          'total_amount': 100,
          'patient_share_cents': 100,
          'status': 'draft',
          'created_at': '2026-09-05T12:22:10.033126+00:00',
        };

    test(
        'sans limit/offset explicites, pagine par offset jusqu\'à une page non pleine',
        () async {
      when(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 0},
        ),
      ).thenAnswer(
        (_) async => fakeResponse(
          List.generate(500, (i) => quoteJson('q$i')),
        ),
      );

      when(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 500},
        ),
      ).thenAnswer(
        (_) async => fakeResponse([quoteJson('q500')]),
      );

      final quotes = await CabinetQuotesApi(apiClient).list();

      expect(quotes.length, 501,
          reason: 'les 2 pages doivent être concaténées');

      verify(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 0},
        ),
      ).called(1);
      verify(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 500},
        ),
      ).called(1);
    });

    test('un seul appel si la première page n\'est pas pleine', () async {
      when(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 0},
        ),
      ).thenAnswer((_) async => fakeResponse([quoteJson('q0')]));

      final quotes = await CabinetQuotesApi(apiClient).list();

      expect(quotes.length, 1);
      verifyNever(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {'limit': 500, 'offset': 500},
        ),
      );
    });

    test('limit/offset explicites : une seule requête, pas d\'auto-pagination',
        () async {
      when(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {
            'patient_id': 'p1',
            'limit': 500,
            'offset': 0,
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse(
          List.generate(500, (i) => quoteJson('q$i')),
        ),
      );

      final quotes = await CabinetQuotesApi(apiClient)
          .list(patientId: 'p1', limit: 500, offset: 0);

      expect(quotes.length, 500);
      verify(
        () => dio.get<dynamic>(
          '/cabinet/quotes',
          queryParameters: {
            'patient_id': 'p1',
            'limit': 500,
            'offset': 0,
          },
        ),
      ).called(1);
    });
  });
}
