import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';

import 'package:app_secretariat/features/dashboard/dashboard_state.dart';
import 'package:app_secretariat/features/dashboard/widgets/practitioners_today_card.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: NubiaTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  group('PractitionersTodayCard', () {
    testWidgets('affiche un état vide sans praticien aujourd\'hui',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const PractitionersTodayCard(practitioners: [])),
      );

      expect(find.byKey(const Key('practitioners_today_card')), findsOneWidget);
      expect(
        find.byKey(const Key('practitioners_today_empty')),
        findsOneWidget,
      );
    });

    testWidgets(
        '#5385 : une ligne par praticien, pastille Présente/Départ selon '
        'la consultation en cours', (tester) async {
      final rousseau = PractitionerToday(
        practitionerId: 'pA',
        practitionerName: 'Dr Amélie Rousseau',
        appointmentCount: 5,
        isInConsultation: true,
        lastAppointmentEndsAt: DateTime(2026, 8, 15, 17),
      );
      final lefevre = PractitionerToday(
        practitionerId: 'pB',
        practitionerName: 'Dr Marc Lefèvre',
        appointmentCount: 4,
        isInConsultation: false,
        lastAppointmentEndsAt: DateTime(2026, 8, 15, 18),
      );

      await tester.pumpWidget(
        _wrap(
          PractitionersTodayCard(practitioners: [rousseau, lefevre]),
        ),
      );

      expect(find.text('Dr Amélie Rousseau'), findsOneWidget);
      expect(find.text('5 RDV · en consultation'), findsOneWidget);
      expect(find.text('Présente'), findsOneWidget);

      expect(find.text('Dr Marc Lefèvre'), findsOneWidget);
      expect(find.text('4 RDV · termine à 18h'), findsOneWidget);
      expect(find.text('Départ 18h'), findsOneWidget);
    });
  });
}
