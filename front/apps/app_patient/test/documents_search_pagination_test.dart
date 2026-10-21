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

void main() {
  setUpAll(() {
    registerFallbackValue(const DocumentsLoadMoreRequested());
  });

  // Première page seule — le document recherché n'y figure pas, il est
  // plus loin dans le coffre-fort (reproduit la repro #8319 : document
  // existant mais pas encore chargé).
  final firstPage = [
    Document(
      id: 'p1',
      name: 'Ordonnance.pdf',
      category: DocumentCategory.prescription,
      createdAt: DateTime(2026, 1, 1),
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    ),
  ];

  late _MockDocumentsBloc mockBloc;

  setUp(() async {
    mockBloc = _MockDocumentsBloc();
    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(() => mockBloc);
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets(
      'recherche avec une page suivante disponible déclenche la pagination '
      'au lieu de conclure « aucun document » (#8319)', (tester) async {
    whenListen(
      mockBloc,
      const Stream<DocumentsState>.empty(),
      initialState: DocumentsLoaded(firstPage, hasMore: true, total: 745),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('documents_search')),
      'ordonnance-ce734ee6',
    );
    // Pas de pumpAndSettle : le shimmer de _DocumentsSkeleton anime en
    // continu (comme l'état de chargement initial) et ne « settle » jamais.
    await tester.pump();
    await tester.pump();

    // Le coffre n'a pas fini d'être parcouru : pas de faux négatif affiché.
    expect(find.byKey(const Key('documents_no_results')), findsNothing);
    verify(
      () => mockBloc.add(any(that: isA<DocumentsLoadMoreRequested>())),
    ).called(greaterThan(0));
  });

  testWidgets(
      'recherche sans correspondance une fois le coffre entièrement '
      'parcouru affiche bien l\'état vide (#8319)', (tester) async {
    whenListen(
      mockBloc,
      const Stream<DocumentsState>.empty(),
      initialState: DocumentsLoaded(firstPage, hasMore: false, total: 1),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('documents_search')),
      'inexistant',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents_no_results')), findsOneWidget);
    verifyNever(
      () => mockBloc.add(any(that: isA<DocumentsLoadMoreRequested>())),
    );
  });
}
