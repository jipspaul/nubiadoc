import 'package:flutter_test/flutter_test.dart';

import 'package:app_pharmacie/features/notifications/notification_route_resolver.dart';
import 'package:app_pharmacie/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (pharmacie)', () {
    test('order_received -> file des commandes', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'order_received'),
        AppRouter.orders,
      );
    });

    test('order_status_changed -> file des commandes', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'order_status_changed'),
        AppRouter.orders,
      );
    });

    test('stock_request_received -> stock', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'stock_request_received'),
        AppRouter.stock,
      );
    });

    test('pharmacy_quote_sent -> devis', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'pharmacy_quote_sent'),
        AppRouter.devis,
      );
    });

    test('pharmacy_quote_decided -> devis', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'pharmacy_quote_decided'),
        AppRouter.devis,
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
