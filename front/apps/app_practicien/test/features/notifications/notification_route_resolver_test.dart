import 'package:flutter_test/flutter_test.dart';

import 'package:app_practicien/features/notifications/notification_route_resolver.dart';
import 'package:app_practicien/router/app_router.dart';

void main() {
  group('NotificationRouteResolver (praticien)', () {
    test('patient_checked_in -> salle d\'attente', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'patient_checked_in'),
        AppRouter.waitingRoom,
      );
    });

    test('quote_signed -> devis', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'quote_signed'),
        AppRouter.devis,
      );
    });

    test('labo -> bons (lab work orders)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'labo'),
        AppRouter.labWorkOrders,
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

    test('kind inconnu -> null (pas de navigation, pas de crash)', () {
      expect(
        NotificationRouteResolver.resolve(kind: 'stock'),
        isNull,
      );
    });

    test('kind null -> null', () {
      expect(NotificationRouteResolver.resolve(kind: null), isNull);
    });
  });
}
