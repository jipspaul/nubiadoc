// Régression #7578 — GET /v1/cabinet/stock-requests (et son pendant
// pharmacie) plafonne à 200 lignes par défaut côté back
// (`ListStockRequestsQuery`, `api/src/pharmacy/stock.rs`) mais accepte
// `?limit=` jusqu'à 500. Sans ce paramètre explicite, `PharmacyStockApi.list`
// se contentait du défaut serveur et tronquait silencieusement les demandes
// au-delà des 200 premières (`created_at DESC`) — 27 demandes sur 227
// invisibles côté secrétariat, dont 4 encore `sent` en attente de réponse
// pharmacie.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/pharmacy_stock/pharmacy_stock_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  late MockApiClient apiClient;
  late MockDio dio;

  setUp(() {
    apiClient = MockApiClient();
    dio = MockDio();
    when(() => apiClient.dio).thenReturn(dio);
  });

  Response<T> fakeResponse<T>(T? data) =>
      Response<T>(data: data, requestOptions: RequestOptions(path: ''));

  group('PharmacyStockApi.list (#7578)', () {
    test('demande explicitement limit=500, pas le défaut serveur (200)',
        () async {
      final api = PharmacyStockApi(apiClient, basePath: '/cabinet');
      when(
        () => dio.get<dynamic>(
          '/cabinet/stock-requests',
          queryParameters: {'limit': 500},
        ),
      ).thenAnswer((_) async => fakeResponse<dynamic>([]));

      await api.list();

      verify(
        () => dio.get<dynamic>(
          '/cabinet/stock-requests',
          queryParameters: {'limit': 500},
        ),
      ).called(1);
    });
  });
}
