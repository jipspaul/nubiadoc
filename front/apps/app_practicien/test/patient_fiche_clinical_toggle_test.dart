import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_fiche.dart';

class _MockListPatientDocuments extends Mock
    implements ListPatientDocumentsUseCase {}

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

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
    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocuments,
    );

    final listJournal = _MockListPatientJournal();
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientJournalUseCase>(
      () => listJournal,
    );

    addTearDown(GetIt.instance.reset);
  });

  // #4971 : la section « Notes cliniques » a été retirée de l'onglet Résumé
  // au profit du journal chronologique unique (`PatientJournalSection`) —
  // `ClinicalSection` n'y est donc plus jamais rendue. La clé/bouton
  // `toggle_clinical` reste conservée (portée future : filtrer le journal),
  // ce test vérifie juste qu'elle survit et reste actionnable sans erreur.
  group('PatientFiche — toggle notes cliniques', () {
    testWidgets('le bouton toggle_clinical reste présent et actionnable',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('toggle_clinical')), findsOneWidget);
      expect(find.byKey(const Key('clinical_section')), findsNothing);

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pump();

      expect(find.byKey(const Key('toggle_clinical')), findsOneWidget);
      expect(find.byKey(const Key('clinical_section')), findsNothing);
    });
  });
}
