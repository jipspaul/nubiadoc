import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/consultation_clinique/widgets/patient_alerts_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(body: child),
      );

  testWidgets('liste vide → widget masqué (jamais d\'alerte inventée)',
      (tester) async {
    await tester.pumpWidget(wrap(const PatientAlertsBox(alerts: [])));

    expect(find.byKey(const Key('patient_alerts_box')), findsNothing);
    expect(find.text('Alertes du dossier'), findsNothing);
  });

  testWidgets('une ligne par alerte, icône dédiée par kind', (tester) async {
    await tester.pumpWidget(wrap(const PatientAlertsBox(alerts: [
      MedicalAlert(kind: 'allergie', label: 'Pénicilline'),
      MedicalAlert(kind: 'medico_legal', label: 'Anticoagulant (AVK)'),
    ])));

    expect(find.byKey(const Key('patient_alerts_box')), findsOneWidget);
    expect(find.text('Allergie Pénicilline'), findsOneWidget);
    expect(find.text('Anticoagulant (AVK)'), findsOneWidget);
    expect(find.byIcon(Icons.medication), findsOneWidget);
    expect(find.byIcon(Icons.healing), findsOneWidget);
    expect(find.byIcon(Icons.warning), findsOneWidget);
  });
}
