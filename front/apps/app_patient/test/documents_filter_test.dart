import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_page.dart';
import 'package:app_patient/features/documents/documents_state.dart';

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

final _docs = [
  Document(
    id: 'p1',
    name: 'Ordonnance test.pdf',
    category: DocumentCategory.prescription,
    createdAt: DateTime(2026, 1, 1),
    fileSizeBytes: 1024,
    mimeType: 'application/pdf',
  ),
  Document(
    id: 'r1',
    name: 'Compte rendu test.pdf',
    category: DocumentCategory.report,
    createdAt: DateTime(2026, 1, 2),
    fileSizeBytes: 2048,
    mimeType: 'application/pdf',
  ),
  Document(
    id: 'i1',
    name: 'Radio test.pdf',
    category: DocumentCategory.xray,
    createdAt: DateTime(2026, 1, 3),
    fileSizeBytes: 4096,
    mimeType: 'application/pdf',
  ),
];

void main() {
  late _MockDocumentsBloc bloc;

  setUpAll(() {
    registerFallbackValue(const DocumentsLoadRequested());
  });

  setUp(() async {
    bloc = _MockDocumentsBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(() => bloc);
  });

  tearDown(() async => GetIt.instance.reset());

  group('DocumentsPage — filtre par catégorie (FR1.31)', () {
    testWidgets(
        'état initial — chip « Tous » sélectionné, tous les documents visibles',
        (tester) async {
      whenListen(
        bloc,
        Stream<DocumentsState>.empty(),
        initialState: DocumentsLoaded(_docs),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DocumentsPage())),
      );
      await tester.pumpAndSettle();

      final tousChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Tous'),
      );
      expect(tousChip.selected, isTrue);

      expect(find.byKey(const Key('document_p1')), findsOneWidget);
      expect(find.byKey(const Key('document_r1')), findsOneWidget);
      expect(find.byKey(const Key('document_i1')), findsOneWidget);
    });

    testWidgets(
        'tap chip « Ordonnance » — seuls les documents category==prescription visibles',
        (tester) async {
      whenListen(
        bloc,
        Stream<DocumentsState>.empty(),
        initialState: DocumentsLoaded(_docs),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DocumentsPage())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Ordonnance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document_p1')), findsOneWidget);
      expect(find.byKey(const Key('document_r1')), findsNothing);
      expect(find.byKey(const Key('document_i1')), findsNothing);
    });

    testWidgets(
        'tap chip « Tous » après filtrage — reset, tous les documents visibles',
        (tester) async {
      whenListen(
        bloc,
        Stream<DocumentsState>.empty(),
        initialState: DocumentsLoaded(_docs),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: DocumentsPage())),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Ordonnance'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document_r1')), findsNothing);

      await tester.tap(find.widgetWithText(FilterChip, 'Tous'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document_p1')), findsOneWidget);
      expect(find.byKey(const Key('document_r1')), findsOneWidget);
      expect(find.byKey(const Key('document_i1')), findsOneWidget);
    });
  });
}
