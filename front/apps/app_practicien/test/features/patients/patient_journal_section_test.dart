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

  Future<void> pumpSection(WidgetTester tester) => tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(
            body: PatientJournalSection(patientId: 'pat-1'),
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
}
