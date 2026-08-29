import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_practicien/features/patients/patient_journal_section.dart';

class _MockListPatientJournal extends Mock
    implements ListPatientJournalUseCase {}

void main() {
  late _MockListPatientJournal listJournal;

  setUp(() {
    listJournal = _MockListPatientJournal();
    GetIt.instance.registerFactory<ListPatientJournalUseCase>(
      () => listJournal,
    );
    addTearDown(GetIt.instance.reset);
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    bool showClinical = true,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: Scaffold(
            body: PatientJournalSection(
              patientId: 'pat-1',
              showClinical: showClinical,
            ),
          ),
        ),
      );

  testWidgets('affiche un skeleton pendant le chargement', (tester) async {
    when(() => listJournal(any())).thenAnswer(
      (_) async => Future.delayed(
        const Duration(milliseconds: 50),
        () => const Right([]),
      ),
    );

    await pumpSection(tester);

    expect(find.byKey(const Key('patient_journal_skeleton')), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('affiche un message clair quand le journal est vide',
      (tester) async {
    when(() => listJournal(any())).thenAnswer((_) async => const Right([]));

    await pumpSection(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_journal_empty')), findsOneWidget);
    expect(find.byKey(const Key('patient_journal_entries')), findsNothing);
  });

  testWidgets('affiche les entrées triées en chronologie décroissante',
      (tester) async {
    final today = DateTime.now();
    when(() => listJournal(any())).thenAnswer(
      (_) async => Right([
        PatientJournalEntry(
          date: today,
          kind: PatientJournalKind.acte,
          title: 'Traitement endodontique',
          subtitle: 'HBFD001',
          tags: const ['Dent 26', 'Dr A. Rousseau'],
          amountCents: 9350,
        ),
        PatientJournalEntry(
          date: DateTime(2026, 8, 10),
          kind: PatientJournalKind.ordonnance,
          title: 'Ordonnance',
          subtitle: 'Amoxicilline 1 g',
          tags: const ['3 ligne(s)'],
        ),
      ]),
    );

    await pumpSection(tester);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_journal_entries')), findsOneWidget);
    expect(find.byKey(const Key('patient_journal_entry_0')), findsOneWidget);
    expect(find.byKey(const Key('patient_journal_entry_1')), findsOneWidget);

    // Acte : titre + code CCAM en pastille monospace + montant tabulaire.
    expect(find.text('Traitement endodontique'), findsOneWidget);
    expect(find.text('HBFD001'), findsOneWidget);
    expect(find.text('93,50 €'), findsOneWidget);
    expect(find.text('aujourd\'hui'), findsOneWidget);
    expect(find.text('Dent 26'), findsOneWidget);

    // Ordonnance : pas de pastille CCAM, sous-titre affiché normalement.
    expect(find.text('Ordonnance'), findsOneWidget);
    expect(find.text('Amoxicilline 1 g'), findsOneWidget);
    expect(find.text('10 août'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });

  testWidgets('affiche le message d\'erreur en cas d\'échec', (tester) async {
    when(() => listJournal(any())).thenAnswer(
      (_) async => const Left(NetworkFailure()),
    );

    await pumpSection(tester);
    await tester.pumpAndSettle();

    expect(find.text('Erreur réseau. Vérifiez votre connexion.'),
        findsOneWidget);
  });

  testWidgets(
      'affiche les six filtres, « Tout » sélectionné par défaut, et filtre '
      'la timeline en place', (tester) async {
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
      ]),
    );

    await pumpSection(tester);
    await tester.pumpAndSettle();

    for (final label in [
      'Tout',
      'Actes',
      'Ordonnances',
      'Documents',
      'Devis',
      'Rendez-vous',
    ]) {
      expect(find.text(label), findsOneWidget);
    }

    expect(find.byKey(const Key('patient_journal_entry_0')), findsOneWidget);
    expect(find.byKey(const Key('patient_journal_entry_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('patient_journal_filter_acte')));
    await tester.pumpAndSettle();

    expect(find.text('Traitement endodontique'), findsOneWidget);
    expect(find.text('Ordonnance'), findsNothing);
    expect(find.byKey(const Key('patient_journal_entry_1')), findsNothing);

    await tester.tap(find.byKey(const Key('patient_journal_filter_all')));
    await tester.pumpAndSettle();

    expect(find.text('Traitement endodontique'), findsOneWidget);
    expect(find.text('Ordonnance'), findsOneWidget);
  });

  // #4976, maquette design-v2 point 4 — `showClinical: false` masque ce qui
  // est réellement clinique (actes, ordonnances) ; devis/documents/rendez-
  // vous restent visibles.
  testWidgets(
      'showClinical: false masque les actes et ordonnances, garde le reste',
      (tester) async {
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
          date: DateTime(2026, 8, 9),
          kind: PatientJournalKind.ordonnance,
          title: 'Ordonnance',
          subtitle: 'Amoxicilline 1 g',
          tags: const [],
        ),
        PatientJournalEntry(
          date: DateTime(2026, 8, 8),
          kind: PatientJournalKind.devis,
          title: 'Devis implant',
          tags: const [],
        ),
      ]),
    );

    await pumpSection(tester, showClinical: false);
    await tester.pumpAndSettle();

    expect(find.text('Traitement endodontique'), findsNothing);
    expect(find.text('Ordonnance'), findsNothing);
    expect(find.text('Devis implant'), findsOneWidget);
  });
}
