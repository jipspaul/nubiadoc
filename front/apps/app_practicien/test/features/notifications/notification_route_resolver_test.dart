import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/notifications/notification_route_resolver.dart';
import 'package:app_practicien/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (praticien)', () {
    test('waiting_room_called -> salle d\'attente', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'waiting_room_called'),
        AppRouter.waitingRoom,
      );
    });

    test('quote_signed -> devis', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'quote_signed'),
        AppRouter.devis,
      );
    });

    test('lab_work_returned -> bons (lab work orders)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'lab_work_returned'),
        AppRouter.labWorkOrders,
      );
    });

    test('kind inconnu -> null (pas de navigation, pas de crash)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'stock_request_received'),
        isNull,
      );
    });

    test('kind null -> null', () {
      expect(NotificationRouteResolver.resolve(kind: null), isNull);
    });
  });
}
