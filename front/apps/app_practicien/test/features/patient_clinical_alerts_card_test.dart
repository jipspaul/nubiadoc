import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_clinical_alerts_card.dart';

// #4975 — carte « Alertes cliniques » de la colonne gauche du dossier
// patient (maquette design-v2 `praticien-dossier-patient.png`).
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(body: child),
      );

  testWidgets('liste vide → carte masquée (jamais de carte trompeuse)',
      (tester) async {
    await tester.pumpWidget(wrap(const PatientClinicalAlertsCard(
      alerts: [],
    )));

    expect(find.byKey(const Key('patient_clinical_alerts_card')), findsNothing);
    expect(find.text('Alertes cliniques'), findsNothing);
  });

  testWidgets(
      'une ligne par alerte : danger (allergie) en rouge, warn '
      '(medico_legal) en ambre', (tester) async {
    await tester.pumpWidget(wrap(const PatientClinicalAlertsCard(
      alerts: [
        MedicalAlert(kind: 'allergie', label: 'Pénicilline'),
        MedicalAlert(kind: 'medico_legal', label: 'Anticoagulant (AVK)'),
      ],
    )));

    expect(find.byKey(const Key('patient_clinical_alerts_card')), findsOneWidget);
    expect(find.text('Alertes cliniques'), findsOneWidget);
    expect(find.text('Allergie Pénicilline'), findsOneWidget);
    expect(find.text('Anticoagulant (AVK)'), findsOneWidget);

    final dangerRow = tester.widget<Container>(find.byKey(
      const Key('patient_clinical_alert_allergie_Pénicilline'),
    ));
    final warnRow = tester.widget<Container>(find.byKey(
      const Key('patient_clinical_alert_medico_legal_Anticoagulant (AVK)'),
    ));
    final dangerDecoration = dangerRow.decoration! as BoxDecoration;
    final warnDecoration = warnRow.decoration! as BoxDecoration;

    expect(dangerDecoration.color, NubiaColors.dangerBg);
    expect(warnDecoration.color, NubiaColors.warningBg);
  });
}
