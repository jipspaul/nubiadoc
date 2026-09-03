import 'package:flutter_test/flutter_test.dart';

import 'package:app_secretariat/features/notifications/notification_route_resolver.dart';
import 'package:app_secretariat/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (secrétariat)', () {
    test('appointment_requested -> agenda', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'appointment_requested'),
        AppRouter.agenda,
      );
    });

    test('callback_requested -> agenda', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'callback_requested'),
        AppRouter.agenda,
      );
    });

    test('stock_request_received -> stock', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'stock_request_received'),
        AppRouter.stock,
      );
    });

    test('message_received -> messages', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'message_received'),
        AppRouter.messages,
      );
    });

    test('kind inconnu -> null (pas de navigation, pas de crash)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'quote_signed'),
        isNull,
      );
    });

    test('kind null -> null', () {
      expect(NotificationRouteResolver.resolve(kind: null), isNull);
    });
  });
}
