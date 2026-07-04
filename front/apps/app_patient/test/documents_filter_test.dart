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
    Document(
      id: 'o1',
      name: 'Autre.pdf',
      category: DocumentCategory.other,
      createdAt: DateTime(2026, 1, 3),
      fileSizeBytes: 4096,
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

  testWidgets('initial — filtre Tous, tous les docs visibles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter_all')), findsOneWidget);
    expect(find.byKey(const Key('document_p1')), findsOneWidget);
    expect(find.byKey(const Key('document_m1')), findsOneWidget);
    expect(find.byKey(const Key('document_o1')), findsOneWidget);
  });

  testWidgets('tap Ordonnances — seules les ordonnances visibles',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ordonnances'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document_p1')), findsOneWidget);
    expect(find.byKey(const Key('document_m1')), findsNothing);
    expect(find.byKey(const Key('document_o1')), findsNothing);
  });

  testWidgets('tap Tous après filtre — tous les docs visibles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NubiaTheme.light,
        home: const Scaffold(body: DocumentsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Ordonnances'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, 'Tous'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('document_p1')), findsOneWidget);
    expect(find.byKey(const Key('document_m1')), findsOneWidget);
    expect(find.byKey(const Key('document_o1')), findsOneWidget);
  });
}
