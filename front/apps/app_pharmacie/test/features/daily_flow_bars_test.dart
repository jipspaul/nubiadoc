import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';
import 'package:nubia_test_harness/nubia_test_harness.dart';

import 'package:app_pharmacie/features/orders/widgets/daily_flow_bars.dart';

PharmacyOrder orderAt(String id, DateTime createdAt) => PharmacyOrder(
      id: id,
      pharmacyId: 'p1',
      patientDisplayName: 'Jean D.',
      prescriptionId: 'rx1',
      status: PharmacyOrderStatus.received,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

void main() {
  group('DailyFlowBars', () {
    testWidgets('neuf barres, axe horaire et barre courante distinguée',
        (tester) async {
      final now = DateTime.now();
      await tester.pumpApp(
        DailyFlowBars(orders: [
          orderAt('o1', now.subtract(const Duration(hours: 1))),
          orderAt('o2', now),
        ]),
      );

      expect(find.byKey(const Key('daily_flow_bars')), findsOneWidget);
      expect(find.byIcon(Icons.insights), findsOneWidget);
      expect(find.text('Flux de la journée'), findsOneWidget);
      for (var i = 0; i < 9; i++) {
        expect(find.byKey(Key('daily_flow_bar_$i')), findsOneWidget);
      }
      expect(find.text('08h'), findsOneWidget);
      expect(find.text('12h'), findsOneWidget);
      expect(find.text('16h'), findsOneWidget);
      expect(find.text('19h'), findsOneWidget);

      final barDecorations = tester
          .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(FractionallySizedBox),
            matching: find.byType(DecoratedBox),
          ))
          .map((box) => (box.decoration as BoxDecoration).color)
          .toList();
      expect(barDecorations, contains(NubiaColors.brand700));
      expect(barDecorations, contains(NubiaColors.brand200));
    });

    testWidgets('aucune commande aujourd\'hui → graphe masqué',
        (tester) async {
      await tester.pumpApp(const DailyFlowBars(orders: []));

      expect(find.byKey(const Key('daily_flow_bars')), findsNothing);
    });
  });
}
