import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/pharmacy_orders/pharmacy_orders_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #7707 : les facettes de statuts terminaux ajoutées par #7003
  // (« Retirées », « Refusées », « Annulées ») filtrent en mémoire la liste
  // renvoyée par list(), qui n'appelait ni `limit` ni `page.next_cursor` et
  // s'arrêtait donc aux 200 commandes les plus récentes renvoyées par défaut
  // par l'API (`api/src/pharmacy/orders.rs`, `list_pharmacy_orders`), avec
  // jusqu'à 57 commandes terminales anciennes toujours injoignables. Le
  // client doit suivre next_cursor jusqu'à épuisement, comme
  // PatientPharmacyApi.listOrders().
  group('PharmacyOrdersApi.list', () {
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
        () => dio.get<dynamic>(
          '/pharmacy/orders',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order1',
              'pharmacy_id': 'pharm1',
              'prescription_id': 'rx1',
              'status': 'picked_up',
              'created_at': '2026-07-08T08:00:00Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1'},
        }),
      );

      when(
        () => dio.get<dynamic>(
          '/pharmacy/orders',
          queryParameters: <String, dynamic>{
            'limit': 500,
            'cursor': 'CURSOR_1',
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order2',
              'pharmacy_id': 'pharm1',
              'prescription_id': 'rx2',
              'status': 'picked_up',
              'created_at': '2026-07-08T08:03:00Z',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final orders = await PharmacyOrdersApi(apiClient).list();

      expect(orders.length, 2, reason: 'les 2 pages doivent être concaténées');
      expect(orders.map((o) => o.id), containsAll(['order1', 'order2']));

      verify(
        () => dio.get<dynamic>(
          '/pharmacy/orders',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).called(1);
      verify(
        () => dio.get<dynamic>(
          '/pharmacy/orders',
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
          '/pharmacy/orders',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order1',
              'pharmacy_id': 'pharm1',
              'prescription_id': 'rx1',
              'status': 'received',
              'created_at': '2026-07-08T08:00:00Z',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final orders = await PharmacyOrdersApi(apiClient).list();

      expect(orders.length, 1);
      verify(
        () => dio.get<dynamic>(
          '/pharmacy/orders',
          queryParameters: <String, dynamic>{'limit': 500},
        ),
      ).called(1);
    });
  });
}
