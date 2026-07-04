// Issue #3349 — les cartes documents affichaient « 0 Ko » pour tout fichier :
// l'API liste ne renvoyait pas la taille et le formatage arrondissait à 0.
// Désormais : taille masquée si inconnue (0), « X Ko » (arrondi supérieur,
// jamais 0) sinon, « X,Y Mo » au-delà de 1 Mo.
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

Document _doc(String id, int sizeBytes) => Document(
      id: id,
      name: '$id.pdf',
      category: DocumentCategory.prescription,
      createdAt: DateTime(2026, 1, 1),
      fileSizeBytes: sizeBytes,
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

  testWidgets('taille inconnue (0) → aucun « 0 Ko » affiché', (tester) async {
    await pump(tester, [_doc('sans-taille', 0)]);

    expect(find.textContaining('0 Ko'), findsNothing);
    expect(find.textContaining('Ko'), findsNothing);
  });

  testWidgets('petit fichier → affiché en octets, jamais « 0 Ko »',
      (tester) async {
    await pump(tester, [_doc('petit', 512)]);

    expect(find.textContaining('512 o'), findsOneWidget);
  });

  testWidgets('100 Ko affichés', (tester) async {
    await pump(tester, [_doc('moyen', 102400)]);

    expect(find.textContaining('100 Ko'), findsOneWidget);
  });

  testWidgets('gros fichier affiché en Mo', (tester) async {
    await pump(tester, [_doc('gros', 1572864)]); // 1.5 Mo

    expect(find.textContaining('1.5 Mo'), findsOneWidget);
  });
}
