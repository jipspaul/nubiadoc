import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListPatientTags extends Mock implements ListPatientTagsUseCase {}

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockGetCabinetMedicalQuestionnaire extends Mock
    implements GetCabinetMedicalQuestionnaireUseCase {}

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
  setUp(() {
    final listTags = _MockListPatientTags();
    when(() => listTags(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientTagsUseCase>(() => listTags);

    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocuments,
    );

    final getQuestionnaire = _MockGetCabinetMedicalQuestionnaire();
    when(() => getQuestionnaire(any()))
        .thenAnswer((_) async => const Right(null));
    GetIt.instance.registerFactory<GetCabinetMedicalQuestionnaireUseCase>(
      () => getQuestionnaire,
    );

    addTearDown(GetIt.instance.reset);
  });

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
