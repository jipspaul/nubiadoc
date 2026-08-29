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

class _MockGetMedicalRecord extends Mock implements GetMedicalRecordUseCase {}

class _MockListTreatmentPlans extends Mock
    implements ListTreatmentPlansUseCase {}

class _MockListOrthodonticTreatments extends Mock
    implements ListOrthodonticTreatmentsUseCase {}

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
  late _MockListPatientJournal listJournal;
  late _MockGetMedicalRecord getMedicalRecord;

  setUp(() {
    final listDocuments = _MockListPatientDocuments();
    when(() => listDocuments(any(), category: any(named: 'category')))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocuments,
    );

    listJournal = _MockListPatientJournal();
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListPatientJournalUseCase>(
      () => listJournal,
    );

    getMedicalRecord = _MockGetMedicalRecord();
    when(() => getMedicalRecord(any())).thenAnswer(
      (_) async =>
          const Right(MedicalRecordSummary(allergies: [], treatments: [])),
    );
    GetIt.instance.registerFactory<GetMedicalRecordUseCase>(
      () => getMedicalRecord,
    );

    // #4982 — onglet « Plans de traitement », adjacent à l'onglet initial
    // (Journal) : `TabBarView` le pré-construit (cache du `PageView`),
    // donc son `initState` s'exécute même sans y naviguer.
    final listTreatmentPlans = _MockListTreatmentPlans();
    when(() => listTreatmentPlans(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListTreatmentPlansUseCase>(
      () => listTreatmentPlans,
    );

    final listOrthodonticTreatments = _MockListOrthodonticTreatments();
    when(() => listOrthodonticTreatments(any()))
        .thenAnswer((_) async => const Right([]));
    GetIt.instance.registerFactory<ListOrthodonticTreatmentsUseCase>(
      () => listOrthodonticTreatments,
    );

    addTearDown(GetIt.instance.reset);
  });

  // #4971 : la section « Notes cliniques » a été retirée de l'onglet Résumé
  // au profit du journal chronologique unique (`PatientJournalSection`) —
  // `ClinicalSection` n'y est donc plus jamais rendue. La clé/bouton
  // `toggle_clinical` reste conservée.
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

    // #4976, maquette design-v2 point 4 — `toggle_clinical` doit désormais
    // couvrir ce qui est réellement clinique (journal des actes,
    // ordonnances, alertes), pas seulement naissance + dernière visite.
    testWidgets(
        'masque le journal des actes/ordonnances et les alertes cliniques, '
        'garde le reste visible', (tester) async {
      when(() => listJournal(any())).thenAnswer(
        (_) async => Right([
          PatientJournalEntry(
            date: DateTime(2026, 8, 10),
            kind: PatientJournalKind.acte,
            title: 'Traitement endodontique',
            subtitle: 'HBFD001',
            tags: const [],
          ),
          PatientJournalEntry(
            date: DateTime(2026, 8, 5),
            kind: PatientJournalKind.ordonnance,
            title: 'Ordonnance',
            subtitle: 'Amoxicilline 1 g',
            tags: const [],
          ),
          PatientJournalEntry(
            date: DateTime(2026, 8, 1),
            kind: PatientJournalKind.devis,
            title: 'Devis implant',
            subtitle: '1 200,00 €',
            tags: const [],
          ),
        ]),
      );
      when(() => getMedicalRecord(any())).thenAnswer(
        (_) async => const Right(
          MedicalRecordSummary(
            allergies: [],
            treatments: [],
            medicalAlerts: [MedicalAlert(kind: 'allergie', label: 'Iode')],
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
            theme: NubiaTheme.light, home: PatientFiche(patient: _patient)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Traitement endodontique'), findsOneWidget);
      expect(find.text('Ordonnance'), findsOneWidget);
      expect(find.text('Devis implant'), findsOneWidget);
      expect(
        find.byKey(const Key('patient_fiche_alert_pill_allergie_Iode')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pumpAndSettle();

      expect(find.text('Traitement endodontique'), findsNothing);
      expect(find.text('Ordonnance'), findsNothing);
      expect(
        find.byKey(const Key('patient_fiche_alert_pill_allergie_Iode')),
        findsNothing,
      );
      // Contenu non clinique : reste visible.
      expect(find.text('Devis implant'), findsOneWidget);

      await tester.tap(find.byKey(const Key('toggle_clinical')));
      await tester.pumpAndSettle();

      expect(find.text('Traitement endodontique'), findsOneWidget);
      expect(find.text('Ordonnance'), findsOneWidget);
      expect(
        find.byKey(const Key('patient_fiche_alert_pill_allergie_Iode')),
        findsOneWidget,
      );
    });
  });
}
