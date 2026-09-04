import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/features/notifications/notification_route_resolver.dart';
import 'package:app_patient/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (patient)', () {
    test('type appointment avec id -> mesRdv?id=', () {
      expect(
        NotificationRouteResolver.resolve(type: 'appointment', targetId: 'a1'),
        '${AppRouter.mesRdv}?id=a1',
      );
    });

    test('deepLink /appointments/<id> -> mesRdv?id=', () {
      expect(
        NotificationRouteResolver.resolve(deepLink: '/appointments/a1'),
        '${AppRouter.mesRdv}?id=a1',
      );
    });

    // #6482 : l'API (`derive_deep_link`, api/src/notifications.rs) émet
    // `/messages/<conversation_id>` pour `message_received`, mais la route
    // déclarée côté patient est `/messaging/:id` (app_router.dart:390).
    test('deepLink /messages/<id> -> messaging/<id>', () {
      expect(
        NotificationRouteResolver.resolve(deepLink: '/messages/c1'),
        '${AppRouter.messaging}/c1',
      );
    });

    test('deepLink /messages (sans id) -> messaging', () {
      expect(
        NotificationRouteResolver.resolve(deepLink: '/messages'),
        AppRouter.messaging,
      );
    });

    test('deepLink /pharmacy/orders/<id> inchangé (route déjà existante)', () {
      expect(
        NotificationRouteResolver.resolve(deepLink: '/pharmacy/orders/o1'),
        '/pharmacy/orders/o1',
      );
    });

    test('type et deepLink absents -> null', () {
      expect(NotificationRouteResolver.resolve(), isNull);
    });
  });
}
