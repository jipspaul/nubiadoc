//! Tests widget : `PatientDocumentsSection` (#4042) — liste vide/remplie.

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

PatientDocument _doc(String suffix) => PatientDocument(
      id: 'doc-$suffix',
      category: 'ordonnance',
      filename: 'ordonnance_$suffix.pdf',
      mimeType: 'application/pdf',
      sizeBytes: 54321,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late _MockListPatientDocuments listDocs;

  setUp(() {
    listDocs = _MockListPatientDocuments();
    GetIt.instance.registerFactory<ListPatientDocumentsUseCase>(
      () => listDocs,
    );
    addTearDown(GetIt.instance.reset);
  });

  Widget buildSection() => MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: const PatientDocumentsSection(patientId: 'patient-1'),
        ),
      );

  testWidgets('liste vide — affiche le message vide', (tester) async {
    when(() => listDocs('patient-1')).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_documents_empty')), findsOneWidget);
    expect(find.byType(ListRow), findsNothing);
  });

  testWidgets('liste remplie — affiche les documents', (tester) async {
    when(() => listDocs('patient-1')).thenAnswer(
      (_) async => Right([_doc('a'), _doc('b'), _doc('c')]),
    );

    await tester.pumpWidget(buildSection());
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNWidgets(3));
    expect(find.byKey(const Key('patient_documents_empty')), findsNothing);
  });
}
