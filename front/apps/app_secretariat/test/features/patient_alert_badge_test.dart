//! Tests widget : `PatientAlertBadge` (#4093/#4094) — liste avec/sans alerte.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

class _MockListPatientAlerts extends Mock implements ListPatientAlertsUseCase {}

void main() {
  late _MockListPatientAlerts listAlerts;

  setUp(() {
    listAlerts = _MockListPatientAlerts();
    GetIt.instance.registerFactory<ListPatientAlertsUseCase>(() => listAlerts);
    addTearDown(GetIt.instance.reset);
  });

  Widget buildBadge() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientAlertBadge(patientId: 'patient-1'),
        ),
      );

  testWidgets('aucune alerte — badge masqué', (tester) async {
    when(() => listAlerts('patient-1'))
        .thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildBadge());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_alert_badge')), findsNothing);
  });

  testWidgets('au moins une alerte — badge visible avec tooltip',
      (tester) async {
    when(() => listAlerts('patient-1')).thenAnswer(
      (_) async => const Right([
        PatientAlert(
          kind: 'unpaid_invoice',
          message: 'Facture signée impayée depuis plus de 30 jours.',
        ),
      ]),
    );

    await tester.pumpWidget(buildBadge());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_alert_badge')), findsOneWidget);
    final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
    expect(
      tooltip.message,
      'Facture signée impayée depuis plus de 30 jours.',
    );
  });
}
