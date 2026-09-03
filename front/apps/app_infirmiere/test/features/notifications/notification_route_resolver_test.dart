import 'package:flutter_test/flutter_test.dart';

import 'package:app_infirmiere/features/notifications/notification_route_resolver.dart';
import 'package:app_infirmiere/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (infirmière)', () {
    test('visit_offer -> accueil (onglet Offres)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'visit_offer'),
        AppRouter.home,
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
