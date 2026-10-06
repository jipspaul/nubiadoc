// Issue #8075 — la maquette design-v2 prescrit un sous-titre de comptage
// sous le titre « Mes documents » (« N documents · M ajoutés cette
// semaine ») : le volume du coffre-fort et sa fraîcheur, d'un coup d'œil.
// Le live n'affichait que le titre, l'information existant pourtant déjà
// côté état (compteur des facettes, total du groupe « Cette semaine »).
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

Document _doc(String id, DateTime createdAt) => Document(
      id: id,
      name: '$id.pdf',
      category: DocumentCategory.prescription,
      createdAt: createdAt,
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
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

  testWidgets(
      'affiche « N documents · M ajoutés cette semaine » sous le titre',
      (tester) async {
    final now = DateTime.now();
    await pump(tester, [
      _doc('r1', now.subtract(const Duration(days: 1))),
      _doc('r2', now.subtract(const Duration(days: 3))),
      _doc('m1', DateTime(now.year, now.month - 1, 15)),
    ]);

    expect(
      find.byKey(const Key('documents_count_subtitle')),
      findsOneWidget,
    );
    expect(find.text('3 documents · 2 ajoutés cette semaine'), findsOneWidget);
  });

  testWidgets('accords au singulier quand un seul document / un seul ajout',
      (tester) async {
    final now = DateTime.now();
    await pump(tester, [_doc('r1', now.subtract(const Duration(days: 1)))]);

    expect(find.text('1 document · 1 ajouté cette semaine'), findsOneWidget);
  });
}
