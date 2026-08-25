//! Tests widget : `PatientBalanceSection` (#4045) — solde=0 et solde>0,
//! (#4090) — compteur de rendez-vous manqués (`noShowCount`) 0 et 3, même fetch,
//! (#4092) — indicateur tuteur, patient avec vs sans tuteur déclaré.

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

class _MockGetCabinetPatient extends Mock implements GetCabinetPatientUseCase {}

CabinetPatient _patient({
  int? balanceDueCents,
  int? noShowCount,
  List<GuardianshipLink>? guardians,
}) =>
    CabinetPatient(
      id: 'patient-1',
      cabinetId: 'c1',
      firstName: 'Marc',
      lastName: 'Solde',
      createdAt: DateTime(2026, 1, 1),
      balanceDueCents: balanceDueCents,
      noShowCount: noShowCount,
      guardians: guardians,
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

  testWidgets(
      'solde > 999 € : séparateur de milliers (#5123, NubiaMoney.formatCents)',
      (tester) async {
    when(() => getPatient('patient-1'))
        .thenAnswer((_) async => Right(_patient(balanceDueCents: 124567)));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Solde : 1 245,67 €'), findsOneWidget);
  });

  testWidgets('0 rendez-vous manqué : affiché sans mise en avant',
      (tester) async {
    when(() => getPatient('patient-1')).thenAnswer(
      (_) async => Right(_patient(balanceDueCents: 0, noShowCount: 0)),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Rendez-vous manqués : 0'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    expect(text.style?.color, isNull);
  });

  testWidgets('3 rendez-vous manqués : affiché en évidence (couleur error)',
      (tester) async {
    when(() => getPatient('patient-1')).thenAnswer(
      (_) async => Right(_patient(balanceDueCents: 0, noShowCount: 3)),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.text('Rendez-vous manqués : 3'), findsOneWidget);
    final text =
        tester.widget<Text>(find.byKey(const Key('patient_no_show_count')));
    final cs = Theme.of(tester.element(find.byType(Scaffold))).colorScheme;
    expect(text.style?.color, cs.error);
  });

  testWidgets('tuteur déclaré : affiché avec son nom (#4092)', (tester) async {
    when(() => getPatient('patient-1')).thenAnswer(
      (_) async => Right(_patient(guardians: const [
        GuardianshipLink(
          accountId: 'guardian-1',
          firstName: 'Paul',
          lastName: 'Tuteur',
          relationship: 'parent',
        ),
      ])),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_guardians')), findsOneWidget);
    expect(find.text('Tuteur : Paul Tuteur'), findsOneWidget);
  });

  testWidgets('aucun tuteur : indicateur absent (#4092)', (tester) async {
    when(() => getPatient('patient-1')).thenAnswer(
      (_) async => Right(_patient(guardians: const [])),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_guardians')), findsNothing);
  });
}
