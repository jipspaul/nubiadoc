//! Tests widget : `PatientImplantsSection` (#4140/#4141).

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_implants_section.dart';

class _MockCreateImplant extends Mock implements CreateImplantUseCase {}

void main() {
  late _MockCreateImplant createImplant;

  setUp(() {
    createImplant = _MockCreateImplant();
    GetIt.instance.registerFactory<CreateImplantUseCase>(() => createImplant);
    addTearDown(GetIt.instance.reset);
    registerFallbackValue('');
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientImplantsSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('aucun implant à l\'ouverture — affiche le message vide',
      (tester) async {
    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_implants_empty')), findsOneWidget);
  });

  testWidgets(
      'soumettre le formulaire rempli déclenche l\'appel et affiche l\'implant dans la liste',
      (tester) async {
    when(
      () => createImplant(
        patientId: any(named: 'patientId'),
        brand: any(named: 'brand'),
        implantRef: any(named: 'implantRef'),
        lotNumber: any(named: 'lotNumber'),
        placementDate: any(named: 'placementDate'),
        toothPosition: any(named: 'toothPosition'),
        notes: any(named: 'notes'),
      ),
    ).thenAnswer(
      (_) async => const Right(ImplantItem(
        id: 'implant-1',
        brand: 'Nobel Biocare',
        toothPosition: '26',
      )),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('patient_implants_add_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('implant_brand_field')), 'Nobel Biocare');
    await tester.enterText(
        find.byKey(const Key('implant_ref_field')), 'NB-4213');
    await tester.enterText(find.byKey(const Key('implant_tooth_field')), '26');

    await tester.tap(find.byKey(const Key('patient_implant_dialog_confirm')));
    await tester.pumpAndSettle();

    verify(
      () => createImplant(
        patientId: 'patient-1',
        brand: 'Nobel Biocare',
        implantRef: 'NB-4213',
        lotNumber: null,
        placementDate: null,
        toothPosition: '26',
        notes: null,
      ),
    ).called(1);

    expect(find.byKey(const Key('patient_implant_implant-1')), findsOneWidget);
    expect(find.text('Nobel Biocare'), findsOneWidget);
    expect(find.byKey(const Key('patient_implants_empty')), findsNothing);
  });

  testWidgets('échec de création — affiche un snackbar, liste reste vide',
      (tester) async {
    when(
      () => createImplant(
        patientId: any(named: 'patientId'),
        brand: any(named: 'brand'),
        implantRef: any(named: 'implantRef'),
        lotNumber: any(named: 'lotNumber'),
        placementDate: any(named: 'placementDate'),
        toothPosition: any(named: 'toothPosition'),
        notes: any(named: 'notes'),
      ),
    ).thenAnswer(
      (_) async => const Left(
        ServerFailure(message: 'Aucune relation de soin avec ce patient.'),
      ),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('patient_implants_add_button')));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('implant_brand_field')), 'Nobel Biocare');
    await tester.enterText(
        find.byKey(const Key('implant_ref_field')), 'NB-4213');

    await tester.tap(find.byKey(const Key('patient_implant_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(
        find.text('Aucune relation de soin avec ce patient.'), findsOneWidget);
    expect(find.byKey(const Key('patient_implants_empty')), findsOneWidget);
  });
}
