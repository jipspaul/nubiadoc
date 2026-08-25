//! Tests widget : `PatientDocumentsSection` (#4042) — liste vide/remplie.
//! (#5115) — présentation pure : les données viennent du chargement unique
//! de la fiche, l'échec est désormais visible.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_secretariat/features/patients/patients_page.dart';

PatientDocument _doc(String suffix, {String mimeType = 'application/pdf'}) =>
    PatientDocument(
      id: 'doc-$suffix',
      category: 'devis',
      filename: 'devis_$suffix.pdf',
      mimeType: mimeType,
      sizeBytes: 12345,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  Widget buildSection({List<PatientDocument>? documents, String? error}) =>
      MaterialApp(
        theme: NubiaTheme.light,
        home: Scaffold(
          body: PatientDocumentsSection(documents: documents, error: error),
        ),
      );

  testWidgets('liste vide — affiche le message vide', (tester) async {
    await tester.pumpWidget(buildSection(documents: const []));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_documents_empty')), findsOneWidget);
    expect(find.byType(ListRow), findsNothing);
  });

  testWidgets('liste remplie — affiche les documents', (tester) async {
    await tester.pumpWidget(
      buildSection(
        documents: [_doc('a'), _doc('b', mimeType: 'image/png')],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNWidgets(2));
    expect(find.text('devis_a.pdf'), findsOneWidget);
    expect(find.text('devis_b.pdf'), findsOneWidget);
    expect(find.byKey(const Key('patient_documents_empty')), findsNothing);
  });

  // ── Échec visible (#5115) ────────────────────────────────────────────

  testWidgets('échec du chargement — message visible', (tester) async {
    await tester.pumpWidget(buildSection(error: 'Erreur réseau'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('patient_documents_error')), findsOneWidget);
    expect(find.textContaining('Erreur réseau'), findsOneWidget);
    expect(find.byKey(const Key('patient_documents_empty')), findsNothing);
  });
}
