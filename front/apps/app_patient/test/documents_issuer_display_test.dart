// Issue #5219 — la carte document n'affichait pas QUI a déposé le document
// (cabinet / praticien / patient). La provenance devient le premier élément
// de la méta, suivie de la taille ; à défaut de provenance, on retombe sur
// le libellé de catégorie pour ne pas laisser de séparateur « · » orphelin.
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_page.dart';
import 'package:app_patient/features/documents/documents_state.dart';

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

Document _doc(String id, {String? issuer, int fileSizeBytes = 0}) => Document(
      id: id,
      name: '$id.pdf',
      category: DocumentCategory.prescription,
      createdAt: DateTime(2026, 1, 1),
      fileSizeBytes: fileSizeBytes,
      mimeType: 'application/pdf',
      issuer: issuer,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(const DocumentsLoadRequested());
  });

  late _MockDocumentsBloc mockBloc;

  setUp(() async {
    mockBloc = _MockDocumentsBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  Future<void> pump(WidgetTester tester, List<Document> docs) async {
    whenListen(
      mockBloc,
      Stream<DocumentsState>.fromIterable([DocumentsLoaded(docs)])
          .asBroadcastStream(),
      initialState: DocumentsLoaded(docs),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('praticien → provenance affichée en sous-ligne', (tester) async {
    await pump(
      tester,
      [_doc('ordo', issuer: 'Dr A. Rousseau', fileSizeBytes: 98304)],
    );

    expect(find.textContaining('Dr A. Rousseau · 96 Ko'), findsOneWidget);
  });

  testWidgets('cabinet → provenance affichée en sous-ligne', (tester) async {
    await pump(
      tester,
      [_doc('carte', issuer: 'Cabinet Nubia Opéra', fileSizeBytes: 253952)],
    );

    expect(find.textContaining('Cabinet Nubia Opéra · 248 Ko'), findsOneWidget);
  });

  testWidgets('patient → « Ajoutée par vous » affiché en sous-ligne',
      (tester) async {
    await pump(
      tester,
      [_doc('mutuelle', issuer: 'Ajoutée par vous', fileSizeBytes: 1258291)],
    );

    expect(find.textContaining('Ajoutée par vous · 1.2 Mo'), findsOneWidget);
  });

  testWidgets('provenance absente → pas de séparateur orphelin, méta cohérente',
      (tester) async {
    await pump(tester, [_doc('sans-provenance', fileSizeBytes: 102400)]);

    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('· ·'), findsNothing);
    expect(find.textContaining('Ordonnance · 100 Ko'), findsOneWidget);
  });
}
