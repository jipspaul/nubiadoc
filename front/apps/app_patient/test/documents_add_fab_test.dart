import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_page.dart';

class _MockGetDocuments extends Mock implements GetDocumentsUseCase {}

class _MockGetSignedUrl extends Mock implements GetDocumentSignedUrlUseCase {}

class _MockUpload extends Mock implements UploadDocumentUseCase {}

void main() {
  late _MockGetDocuments mockGetDocuments;
  late _MockGetSignedUrl mockGetSignedUrl;
  late _MockUpload mockUpload;

  setUp(() async {
    mockGetDocuments = _MockGetDocuments();
    mockGetSignedUrl = _MockGetSignedUrl();
    mockUpload = _MockUpload();

    await GetIt.instance.reset();
    GetIt.instance.registerFactory<DocumentsBloc>(
      () => DocumentsBloc(
        getDocuments: mockGetDocuments,
        getSignedUrl: mockGetSignedUrl,
        upload: mockUpload,
      ),
    );
  });

  tearDown(() async => GetIt.instance.reset());

  testWidgets(
      '#7427 — le FAB « Ajouter un document » est visible sans défiler même '
      'avec un coffre volumineux', (tester) async {
    final docs = List.generate(
      200,
      (i) => Document(
        id: 'doc-$i',
        name: 'Document $i.pdf',
        category: DocumentCategory.prescription,
        createdAt: DateTime(2026, 1, 1).subtract(Duration(days: i)),
        fileSizeBytes: 1024,
        mimeType: 'application/pdf',
      ),
    );
    when(() => mockGetDocuments()).thenAnswer((_) async => Right(docs));

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    // Sans le moindre scroll, le FAB doit déjà être dans l'arbre — c'est le
    // point d'entrée d'ajout, pas un document enfoui en fin de liste.
    expect(find.byKey(const Key('documents_add_fab')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('documents_add_fab')),
        matching: find.text('Ajouter un document'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('coffre réellement vide — pas de FAB dupliqué avec le CTA '
      'de l\'état vide', (tester) async {
    when(() => mockGetDocuments()).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents_add_fab')), findsNothing);
    expect(find.text('Ajouter un document'), findsOneWidget);
  });
}
