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

    testWidgets(
        'commande pickedUp → « préparation » affiche son propre '
        'preparingAt, pas updatedAt (#6863 : le temps ne doit pas reculer '
        'entre « préparation » et « prête »)', (tester) async {
      final preparingAt = DateTime.utc(2026, 9, 11, 18, 48, 45);
      final pickedUpAt = DateTime.utc(2026, 9, 11, 18, 49, 42);
      final order = PharmacyOrder(
        id: 'o1',
        pharmacyId: 'p1',
        prescriptionId: 'rx1',
        status: PharmacyOrderStatus.pickedUp,
        createdAt: DateTime.utc(2026, 9, 11, 18, 48, 31),
        updatedAt: pickedUpAt,
        preparingAt: preparingAt,
        readyAt: DateTime.utc(2026, 9, 11, 18, 48, 56),
        pickedUpAt: pickedUpAt,
        lineCount: 1,
      );

      await tester.pumpApp(OrderTimeline(order: order));

      final preparingSubtitle = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('timeline_step_preparing')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data)
          .toList();
      String hhmm(DateTime utc) {
        final dt = utc.toLocal();
        return '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}';
      }

      // preparingAt (son propre horodatage), pas pickedUpAt/updatedAt
      // (postérieur — c'était le bug #6863 : le temps reculait au milieu de
      // la timeline).
      expect(preparingSubtitle, contains(contains(hhmm(preparingAt))));
      expect(preparingSubtitle, isNot(contains(contains(hhmm(pickedUpAt)))));
    });
  });
}
