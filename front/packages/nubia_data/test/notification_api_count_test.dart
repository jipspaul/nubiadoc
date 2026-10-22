import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/notifications/notification_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // #8342 : les puces de facette de l'écran Notifications patient
  // plafonnaient à `limit` (`data.length`) au lieu du volume réel de la
  // boîte par famille. count() doit se contenter d'une seule page bornée
  // et lire `page.total` — même correctif que `DocumentApi.count` (#8318).
  group('NotificationApi.count', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('demande une seule page bornée avec ?type= et renvoie page.total',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: <String, dynamic>{'type': 'appointment', 'limit': 1},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'n1',
              'type': 'appointment_confirmed',
              'title': 'RDV confirmé',
              'read': false,
              'created_at': '2026-09-24T09:45:54Z',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'unread_count': 1, 'total': 1589},
        }),
      );

      final total = await NotificationApi(apiClient).count(type: 'appointment');

      expect(total, 1589);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: <String, dynamic>{'type': 'appointment', 'limit': 1},
        ),
      ).called(1);
    });
  });

  // #8342 : `getPage` doit propager `page.total` — alimente la puce
  // « Toutes » sans dépendre de `notifications.length` (borné à une page
  // depuis #8323).
  group('NotificationApi.getPage — total', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('lit page.total indépendamment de la taille de la page chargée',
        () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 20},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'n1',
              'type': 'quote_received',
              'title': 'Devis',
              'read': false,
              'created_at': '2026-09-05T12:22:10.033126+00:00',
            },
          ],
          'page': {'next_cursor': 'CURSOR_1', 'unread_count': 9, 'total': 3659},
        }),
      );

      final page = await NotificationApi(apiClient).getPage();

      expect(page.notifications.length, 1);
      expect(page.total, 3659);
    });
  });
}
