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

    testWidgets(
        "commande pickedUp → l'étape « préparation » ne réutilise pas "
        "updatedAt (postérieur à ready/pickedUp) comme horodatage (#7084)",
        (tester) async {
      final order = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.pickedUp,
        createdAt: DateTime.utc(2026, 9, 17, 0, 13, 15),
        updatedAt: DateTime.utc(2026, 9, 17, 1, 36, 51),
        readyAt: DateTime.utc(2026, 9, 17, 0, 13, 15),
        pickedUpAt: DateTime.utc(2026, 9, 17, 1, 36, 51),
        lineCount: 1,
      );

      await tester.pumpApp(OrderTimeline(order: order));

      // L'heure de retrait (03:36 à Paris) ne doit pas apparaître sous
      // « En cours de préparation », uniquement sous « Retirée ».
      final preparingSubtitle = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('timeline_step_preparing')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      expect(preparingSubtitle, isNot(contains(contains('03:36'))));
      expect(preparingSubtitle, contains('1 médicament'));
    });
  });
}
