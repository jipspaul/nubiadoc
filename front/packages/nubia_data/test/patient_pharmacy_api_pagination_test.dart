import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/patient_pharmacy/patient_pharmacy_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #7554 : l'écran « Mes ordonnances » (patient) n'affichait que
  // les 100 premières ordonnances sur 288 — listPrescriptions() n'appelait
  // ni `limit` ni `page.next_cursor` et s'arrêtait donc à la 1re page
  // renvoyée par l'API (`api/src/prescriptions.rs`, #6381). Le client doit
  // suivre next_cursor jusqu'à épuisement, comme DocumentApi.getAll().
  group('PatientPharmacyApi.listPrescriptions', () {
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
          '/account/prescriptions',
          queryParameters: <String, dynamic>{},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'rx1',
              'status': 'sent',
              'created_at': '2026-09-24T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 100},
        }),
      );

      when(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'rx2',
              'status': 'signed',
              'created_at': '2026-08-10T06:59:08Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final prescriptions = await PatientPharmacyApi(apiClient)
          .listPrescriptions();

      expect(prescriptions.length, 2,
          reason: 'les 2 pages doivent être concaténées');
      expect(prescriptions.map((p) => p.id), containsAll(['rx1', 'rx2']));

      verify(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{},
        ),
      ).called(1);
      verify(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'rx1',
              'status': 'signed',
              'created_at': '2026-09-24T09:45:54Z',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final prescriptions = await PatientPharmacyApi(apiClient)
          .listPrescriptions();

      expect(prescriptions.length, 1);
      verify(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{},
        ),
      ).called(1);
    });

    test('avec limit fourni, une seule page est demandée', () async {
      when(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{'limit': 20},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'rx1',
              'status': 'signed',
              'created_at': '2026-09-24T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'limit': 20},
        }),
      );

      final prescriptions =
          await PatientPharmacyApi(apiClient).listPrescriptions(limit: 20);

      expect(prescriptions.length, 1);
      verifyNever(
        () => dio.get<dynamic>(
          '/account/prescriptions',
          queryParameters: <String, dynamic>{'limit': 20, 'cursor': 'CURSOR_1'},
        ),
      );
    });
  });

  // Régression #7655 : le filtre anti-409 de send_prescription_cubit croise
  // les ordonnances contre listOrders(), qui n'appelait ni `limit` ni
  // `page.next_cursor` et s'arrêtait donc aux 20 commandes les plus
  // récentes renvoyées par défaut par l'API (`api/src/pharmacy/orders.rs`,
  // `list_account_orders`). Le client doit suivre next_cursor jusqu'à
  // épuisement, comme listPrescriptions().
  group('PatientPharmacyApi.listOrders', () {
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
          '/account/orders',
          queryParameters: <String, dynamic>{'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order1',
              'status': 'picked_up',
              'prescription_id': 'rx1',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1'},
        }),
      );

      when(
        () => dio.get<dynamic>(
          '/account/orders',
          queryParameters: <String, dynamic>{
            'limit': 100,
            'cursor': 'CURSOR_1',
          },
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order2',
              'status': 'received',
              'prescription_id': 'rx2',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final orders = await PatientPharmacyApi(apiClient).listOrders();

      expect(orders.length, 2, reason: 'les 2 pages doivent être concaténées');
      expect(orders.map((o) => o.id), containsAll(['order1', 'order2']));

      verify(
        () => dio.get<dynamic>(
          '/account/orders',
          queryParameters: <String, dynamic>{'limit': 100},
        ),
      ).called(1);
      verify(
        () => dio.get<dynamic>(
          '/account/orders',
          queryParameters: <String, dynamic>{
            'limit': 100,
            'cursor': 'CURSOR_1',
          },
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<dynamic>(
          '/account/orders',
          queryParameters: <String, dynamic>{'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'order1',
              'status': 'picked_up',
              'prescription_id': 'rx1',
            },
          ],
          'page': {'next_cursor': null},
        }),
      );

      final orders = await PatientPharmacyApi(apiClient).listOrders();

      expect(orders.length, 1);
      verify(
        () => dio.get<dynamic>(
          '/account/orders',
          queryParameters: <String, dynamic>{'limit': 100},
        ),
      ).called(1);
    });
  });
}
