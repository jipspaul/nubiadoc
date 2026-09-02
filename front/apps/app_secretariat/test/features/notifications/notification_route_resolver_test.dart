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

    test('message_received avec conversation_id -> conversation ciblée', () {
      expect(
        NotificationRouteResolver.resolve(
          kind: 'message_received',
          data: const {'conversation_id': 'conv-42'},
        ),
        '${AppRouter.messages}?conversationId=conv-42',
      );
    });

    test('message_received sans data -> liste des messages', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'message_received'),
        AppRouter.messages,
      );
    });

    test('stock -> stock', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'stock'),
        AppRouter.stock,
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
