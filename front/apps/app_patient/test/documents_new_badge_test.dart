// Issue #5220 — les documents déposés cette semaine (< 7 jours) portent un
// tag « Nouveau » devant la méta et un point sur l'icône ; les documents
// plus anciens n'affichent ni l'un ni l'autre (maquette design-v2, point 2).
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

  testWidgets('document déposé cette semaine → tag et point « Nouveau »',
      (tester) async {
    final recent = _doc('recent', DateTime.now().subtract(
      const Duration(days: 2),
    ));
    await pump(tester, [recent]);

    expect(
      find.descendant(
        of: find.byKey(const Key('document_recent')),
        matching: find.byKey(const Key('document_new_tag')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('document_recent')),
        matching: find.byKey(const Key('document_new_dot')),
      ),
      findsOneWidget,
    );
    expect(find.text('Nouveau'), findsOneWidget);
  });

  testWidgets('document ancien → ni tag ni point', (tester) async {
    final old = _doc('ancien', DateTime.now().subtract(
      const Duration(days: 30),
    ));
    await pump(tester, [old]);

    expect(
      find.descendant(
        of: find.byKey(const Key('document_ancien')),
        matching: find.byKey(const Key('document_new_tag')),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('document_ancien')),
        matching: find.byKey(const Key('document_new_dot')),
      ),
      findsNothing,
    );
    expect(find.text('Nouveau'), findsNothing);
  });
}
