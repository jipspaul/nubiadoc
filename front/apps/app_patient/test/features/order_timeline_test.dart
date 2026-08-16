import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_patient/features/pharmacy_orders/widgets/order_timeline.dart';

void main() {
  group('OrderTimeline (widget)', () {
    PharmacyOrder makeOrder(PharmacyOrderStatus status) => PharmacyOrder(
          id: 'o1',
          pharmacyId: 'p1',
          prescriptionId: 'rx1',
          status: status,
          createdAt: DateTime.utc(2026, 8, 10),
          updatedAt: DateTime.utc(2026, 8, 10, 9, 31),
        );

    testWidgets(
        'commande preparing → étape courante distincte de check_circle, '
        'étapes passées faites, étapes futures à venir', (tester) async {
      await tester.pumpApp(
        OrderTimeline(order: makeOrder(PharmacyOrderStatus.preparing)),
      );

      expect(find.byKey(const Key('timeline_step_received')), findsOneWidget);
      expect(
          find.byKey(const Key('timeline_step_preparing')), findsOneWidget);
      expect(find.byKey(const Key('timeline_step_ready')), findsOneWidget);
      expect(find.byKey(const Key('timeline_step_pickedUp')), findsOneWidget);

      // Étape courante : jamais check_circle, icône métier de l'étape.
      final currentIcon = tester
          .widgetList<Icon>(find.descendant(
            of: find.byKey(const Key('timeline_step_preparing')),
            matching: find.byType(Icon),
          ))
          .first;
      expect(currentIcon.icon, isNot(Icons.check_circle));
      expect(currentIcon.icon, Icons.sync);

      // Étape passée : icône `check`.
      final doneIcon = tester
          .widgetList<Icon>(find.descendant(
            of: find.byKey(const Key('timeline_step_received')),
            matching: find.byType(Icon),
          ))
          .first;
      expect(doneIcon.icon, Icons.check);

      // Étapes à venir : icône `circle` neutre, libellé atténué.
      final upcomingIcon = tester
          .widgetList<Icon>(find.descendant(
            of: find.byKey(const Key('timeline_step_ready')),
            matching: find.byType(Icon),
          ))
          .first;
      expect(upcomingIcon.icon, Icons.circle);

      expect(find.text('En attente de votre passage'), findsOneWidget);
    });
  });
}
