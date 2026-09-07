// Issue #5218 — la carte document n'affichait pas de repère temporel : un
// patient qui cherche « l'ordonnance de la semaine dernière » n'avait aucune
// date. La date de dépôt (createdAt) est affichée au format court FR
// (ex. « 10 août ») dans le titre de la carte (« Ordonnance du 10 août »).
// Issue #6545 — elle n'est plus dupliquée dans la méta (qui ellipsait sur
// toutes les cartes au viewport mobile cible) : la méta reste
// « émetteur · taille », y compris quand la taille est inconnue (pas de
// « 0 Ko »).
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

Document _doc(String id, {required DateTime createdAt, int fileSizeBytes = 0}) =>
    Document(
      id: id,
      name: '$id.pdf',
      category: DocumentCategory.prescription,
      createdAt: createdAt,
      fileSizeBytes: fileSizeBytes,
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
      'la date de dépôt est affichée au format court FR dans le titre, '
      'pas dans la méta', (tester) async {
    await pump(
      tester,
      [
        _doc(
          'ordo',
          createdAt: DateTime(2026, 8, 10),
          fileSizeBytes: 102400,
        ),
      ],
    );

    expect(find.textContaining('Ordonnance du 10 août'), findsOneWidget);
    expect(find.textContaining('Ordonnance · 100 Ko · 10 août'),
        findsNothing);
    expect(find.textContaining('Ordonnance · 100 Ko'), findsOneWidget);
  });

  testWidgets('taille inconnue → pas de « 0 Ko » dans la méta',
      (tester) async {
    await pump(
      tester,
      [_doc('ordo', createdAt: DateTime(2026, 8, 10), fileSizeBytes: 0)],
    );

    expect(find.textContaining('0 Ko'), findsNothing);
    expect(find.textContaining('Ordonnance du 10 août'), findsOneWidget);
  });
}
