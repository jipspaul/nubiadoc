//! Tests widget : `PatientAlertBadge` (#4093/#4094, design-v2 #5113) —
//! pastilles lisibles en colonne, lues depuis `CabinetPatient` (liste),
//! sans fetch ni `Tooltip`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

void main() {
  CabinetPatient patient({
    int? balanceDueCents,
    bool? hasActiveAlerts,
    int? noShowCount,
    List<GuardianshipLink>? guardians,
  }) =>
      CabinetPatient(
        id: 'patient-1',
        cabinetId: 'c1',
        firstName: 'Alice',
        lastName: 'Martin',
        createdAt: DateTime(2026, 1, 1),
        balanceDueCents: balanceDueCents,
        hasActiveAlerts: hasActiveAlerts,
        noShowCount: noShowCount,
        guardians: guardians,
      );

  Widget buildBadge(CabinetPatient patient) => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PatientAlertBadge(patient: patient),
        ),
      );

  testWidgets('aucune donnée d\'alerte — pastille masquée', (tester) async {
    await tester.pumpWidget(buildBadge(patient()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_alert_badge')), findsNothing);
  });

  testWidgets('solde dû — pastille « Impayé » lisible sans survol',
      (tester) async {
    await tester.pumpWidget(buildBadge(patient(balanceDueCents: 14850)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_alert_badge')), findsOneWidget);
    expect(find.text('Impayé'), findsOneWidget);
    // Note #2 de la maquette : plus de `Tooltip`, le texte est déjà là.
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('rendez-vous manqués — pastille « N lapins »', (tester) async {
    await tester.pumpWidget(buildBadge(patient(noShowCount: 2)));
    await tester.pumpAndSettle();

    expect(find.text('2 lapins'), findsOneWidget);
  });

  testWidgets('tuteur renseigné — pastille « Mineur · tuteur »',
      (tester) async {
    await tester.pumpWidget(buildBadge(patient(guardians: const [
      GuardianshipLink(
        accountId: 'g1',
        firstName: 'Paul',
        lastName: 'Martin',
        relationship: 'parent',
      ),
    ])));
    await tester.pumpAndSettle();

    expect(find.text('Mineur · tuteur'), findsOneWidget);
  });

  testWidgets('alerte accueil active sans solde dû — pastille dédiée',
      (tester) async {
    await tester.pumpWidget(buildBadge(patient(hasActiveAlerts: true)));
    await tester.pumpAndSettle();

    expect(find.text('Alerte accueil'), findsOneWidget);
  });
}
