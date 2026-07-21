//! Tests widget : `PatientBalanceSection` (#4045) — solde=0 et solde>0.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

class _MockGetCabinetPatient extends Mock implements GetCabinetPatientUseCase {}

CabinetPatient _patient({int? balanceDueCents}) => CabinetPatient(
      id: 'patient-1',
      cabinetId: 'c1',
      firstName: 'Marc',
      lastName: 'Solde',
      createdAt: DateTime(2026, 1, 1),
      balanceDueCents: balanceDueCents,
    );

void main() {
  late _MockGetCabinetPatient getPatient;

  setUp(() {
    getPatient = _MockGetCabinetPatient();
    GetIt.instance.registerFactory<GetCabinetPatientUseCase>(
      () => getPatient,
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientBalanceSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('solde = 0 : affiché sans mise en avant', (tester) async {
    when(() => getPatient('patient-1'))
        .thenAnswer((_) async => Right(_patient(balanceDueCents: 0)));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Solde : 0,00 €'), findsOneWidget);
    final text = tester.widget<Text>(find.byKey(const Key('patient_balance')));
    expect(text.style?.color, isNull);
  });

  testWidgets('solde > 0 : affiché en évidence (couleur error)',
      (tester) async {
    when(() => getPatient('patient-1'))
        .thenAnswer((_) async => Right(_patient(balanceDueCents: 3050)));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Solde : 30,50 €'), findsOneWidget);
    final text = tester.widget<Text>(find.byKey(const Key('patient_balance')));
    final cs = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(text.style?.color, cs.error);
  });
}
