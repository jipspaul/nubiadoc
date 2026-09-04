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

  final docs = [
    Document(
      id: 'p1',
      name: 'Ordonnance.pdf',
      category: DocumentCategory.prescription,
      createdAt: DateTime(2026, 1, 1),
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    ),
    Document(
      id: 'm1',
      name: 'Mutuelle.pdf',
      category: DocumentCategory.mutualCard,
      createdAt: DateTime(2026, 1, 2),
      fileSizeBytes: 2048,
      mimeType: 'application/pdf',
    ),
  ];

  setUp(() async {
    mockGetDocuments = _MockGetDocuments();
    mockGetSignedUrl = _MockGetSignedUrl();
    mockUpload = _MockUpload();
    when(() => mockGetDocuments()).thenAnswer((_) async => Right(docs));

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
      'recherche sans correspondance — message dédié, pas "aucun document" '
      '(#6487)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('documents_search')),
      'ZZZQQQXX-inexistant',
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents_no_results')), findsOneWidget);
    expect(find.byKey(const Key('documents_empty')), findsNothing);
    expect(
      find.text('Aucun document ne correspond à « ZZZQQQXX-inexistant »'),
      findsOneWidget,
    );
    expect(find.text('Effacer la recherche'), findsOneWidget);
    // La facette « Tous » reste correcte, avec le total réel.
    expect(find.text('Tous 2'), findsOneWidget);
  });

  testWidgets('Effacer la recherche vide le champ et restaure la liste',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('documents_search')),
      'ZZZQQQXX-inexistant',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Effacer la recherche'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents_no_results')), findsNothing);
    expect(find.byKey(const Key('document_p1')), findsOneWidget);
    expect(find.byKey(const Key('document_m1')), findsOneWidget);
    expect(find.text('ZZZQQQXX-inexistant'), findsNothing);
  });

  testWidgets(
      'coffre réellement vide — copie onboarding conservée', (tester) async {
    when(() => mockGetDocuments()).thenAnswer((_) async => const Right([]));

    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents_empty')), findsOneWidget);
    expect(find.text('Aucun document pour l\'instant'), findsOneWidget);
    expect(find.text('Ajouter un document'), findsOneWidget);
  });
}
