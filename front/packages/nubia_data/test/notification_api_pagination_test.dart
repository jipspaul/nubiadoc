import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_core/nubia_core.dart';
import 'package:nubia_data/src/remote/notifications/notification_api.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockDio extends Mock implements Dio {}

void main() {
  // Régression #6633 : la liste des notifications patient était figée aux 20
  // plus récentes — getNotifications() n'appelait ni `limit` ni
  // `page.next_cursor`. Le client doit suivre next_cursor jusqu'à
  // épuisement, comme BillingApi.getQuotes() (#6381).
  group('NotificationApi.getNotifications', () {
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
          '/notifications',
          queryParameters: {'limit': 100},
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
          'page': {'next_cursor': 'CURSOR_1', 'limit': 100},
        }),
      );

      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': [
            {
              'id': 'n2',
              'type': 'appointment_confirmed',
              'title': 'RDV confirmé',
              'read': true,
              'created_at': '2026-08-08T08:00:00.000000+00:00',
            },
          ],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final notifications = await NotificationApi(apiClient).getNotifications();

      expect(notifications.length, 2,
          reason: 'les 2 pages doivent être concaténées');
      expect(notifications.map((n) => n.id), containsAll(['n1', 'n2']));

      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 100, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('un seul appel si next_cursor est absent dès la 1re page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 100},
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
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final notifications = await NotificationApi(apiClient).getNotifications();

      expect(notifications.length, 1);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 100},
        ),
      ).called(1);
    });

    test('unreadOnly ajoute le paramètre unread_only à chaque page', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'unread_only': true, 'limit': 100},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': <Map<String, dynamic>>[],
          'page': {'next_cursor': null, 'limit': 100},
        }),
      );

      final notifications =
          await NotificationApi(apiClient).getNotifications(unreadOnly: true);

      expect(notifications, isEmpty);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'unread_only': true, 'limit': 100},
        ),
      ).called(1);
    });
  });

  // Régression #8323 : la boîte de réception patient suivait next_cursor
  // jusqu'à épuisement avant le premier rendu (37 requêtes séquentielles /
  // 3 629 notifications sur un historique chargé) — même anti-pattern que
  // #8297 pour `/documents`. `getPage()` s'arrête à une seule page.
  group('NotificationApi.getPage', () {
    late MockApiClient apiClient;
    late MockDio dio;

    setUp(() {
      apiClient = MockApiClient();
      dio = MockDio();
      when(() => apiClient.dio).thenReturn(dio);
    });

    Response<Map<String, dynamic>> fakeResponse(Map<String, dynamic> data) =>
        Response(data: data, requestOptions: RequestOptions(path: ''));

    test('ne fait qu\'un seul appel même si next_cursor est présent',
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
          'page': {'next_cursor': 'CURSOR_1', 'limit': 20},
        }),
      );

      final page = await NotificationApi(apiClient).getPage();

      expect(page.notifications.map((n) => n.id), ['n1']);
      expect(page.nextCursor, 'CURSOR_1');
      verifyNever(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 20, 'cursor': 'CURSOR_1'},
        ),
      );
    });

    test('transmet cursor et limit tels que fournis', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 5, 'cursor': 'CURSOR_1'},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': <Map<String, dynamic>>[],
          'page': {'next_cursor': null, 'limit': 5},
        }),
      );

      final page =
          await NotificationApi(apiClient).getPage(limit: 5, cursor: 'CURSOR_1');

      expect(page.notifications, isEmpty);
      expect(page.nextCursor, isNull);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'limit': 5, 'cursor': 'CURSOR_1'},
        ),
      ).called(1);
    });

    test('unreadOnly ajoute le paramètre unread_only', () async {
      when(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'unread_only': true, 'limit': 20},
        ),
      ).thenAnswer(
        (_) async => fakeResponse({
          'data': <Map<String, dynamic>>[],
          'page': {'next_cursor': null, 'limit': 20},
        }),
      );

      final page =
          await NotificationApi(apiClient).getPage(unreadOnly: true);

      expect(page.notifications, isEmpty);
      verify(
        () => dio.get<Map<String, dynamic>>(
          '/notifications',
          queryParameters: {'unread_only': true, 'limit': 20},
        ),
      ).called(1);
    });
  });
}
