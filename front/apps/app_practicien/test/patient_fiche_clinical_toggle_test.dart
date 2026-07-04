import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

final _patient = CabinetPatient(
  id: 'pat-1',
  cabinetId: 'cab-1',
  firstName: 'Jean',
  lastName: 'Dupont',
  email: 'jean.dupont@example.com',
  phone: '0600000001',
  createdAt: DateTime(2024, 1, 1),
);

void main() {
  group('PatientFiche — toggle notes cliniques', () {
    testWidgets('tap masque la section clinique', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('clinical_section')), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pump();

      expect(find.byKey(const Key('clinical_section')), findsNothing);
    });

    testWidgets('re-tap réaffiche la section clinique', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pump();
      expect(find.byKey(const Key('clinical_section')), findsNothing);

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pump();
      expect(find.byKey(const Key('clinical_section')), findsOneWidget);
    });
  });
}
