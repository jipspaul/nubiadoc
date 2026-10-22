// Issue #8393 — régression de #8363 : quand la requête serveur d'une
// catégorie ÉCHOUE (500, coupure réseau…), `_onFilterChanged` écrasait le
// `Failure` par une liste vide, rendant l'écran strictement identique à une
// catégorie réellement vide — « Aucun document dans cette catégorie » —
// alors que la puce elle-même annonce toujours son compte serveur. Même
// doctrine que `isLoadingCategory` (#8363) : un échec ne doit jamais se
// faire passer pour un verdict « vide ».
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
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

class _MockGetDocuments extends Mock implements GetDocumentsUseCase {}

class _MockGetSignedUrl extends Mock implements GetDocumentSignedUrlUseCase {}

class _MockUpload extends Mock implements UploadDocumentUseCase {}

class _MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

void main() {
  group('échec de la requête de catégorie (bloc réel)', () {
    late _MockGetDocuments mockGetDocuments;
    late _MockGetSignedUrl mockGetSignedUrl;
    late _MockUpload mockUpload;

    final firstPage = [
      Document(
        id: 'doc-0',
        name: 'Ordonnance 0.pdf',
        category: DocumentCategory.prescription,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024,
        mimeType: 'application/pdf',
      ),
    ];

    setUp(() async {
      mockGetDocuments = _MockGetDocuments();
      mockGetSignedUrl = _MockGetSignedUrl();
      mockUpload = _MockUpload();
      when(() => mockGetDocuments.getPage(
            limit: any(named: 'limit'),
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer(
        (_) async =>
            Right((documents: firstPage, nextCursor: null, total: 15)),
      );
      when(() => mockGetDocuments.categoryCounts(
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer(
        (_) async => const Right({DocumentCategory.photo: 15}),
      );

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
        'requête serveur en 500 sur « Photo 15 » — erreur relançable, '
        'jamais « Aucun document dans cette catégorie » (#8393)',
        (tester) async {
      when(() => mockGetDocuments.call(
            category: DocumentCategory.photo,
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer(
        (_) async => const Left(
          ServerFailure(message: 'Erreur serveur.', statusCode: 500),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_no_results')), findsNothing);
      expect(find.byKey(const Key('documents_category_error')), findsOneWidget);
      expect(find.text('Erreur serveur.'), findsOneWidget);

      // Relance : un nouveau succès remplace l'erreur par les documents.
      when(() => mockGetDocuments.call(
            category: DocumentCategory.photo,
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer((_) async => Right(firstPage));

      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_category_error')), findsNothing);
      expect(find.byKey(const Key('document_doc-0')), findsOneWidget);
    });

    testWidgets(
        'coupure réseau (exception) sur « Photo 15 » — même erreur '
        'relançable que le 500 (#8393)', (tester) async {
      when(() => mockGetDocuments.call(
            category: DocumentCategory.photo,
            patientAccount: any(named: 'patientAccount'),
          )).thenThrow(Exception('network down'));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter_photo')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_no_results')), findsNothing);
      expect(find.byKey(const Key('documents_category_error')), findsOneWidget);
    });
  });

  group('état catégorie en échec (bloc simulé)', () {
    late _MockDocumentsBloc mockBloc;

    setUpAll(() {
      registerFallbackValue(const DocumentsFilterChanged(null));
    });

    setUp(() async {
      mockBloc = _MockDocumentsBloc();
      await GetIt.instance.reset();
      GetIt.instance.registerFactory<DocumentsBloc>(() => mockBloc);
    });

    tearDown(() async => GetIt.instance.reset());

    testWidgets(
        'categoryError non nul — bouton Réessayer renvoie '
        'DocumentsFilterChanged sur la même catégorie (#8393)', (tester) async {
      whenListen(
        mockBloc,
        const Stream<DocumentsState>.empty(),
        initialState: const DocumentsLoaded(
          [],
          activeFilter: DocumentCategory.photo,
          total: 15,
          categoryCounts: {DocumentCategory.photo: 15},
          categoryError: 'Erreur serveur.',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('documents_no_results')), findsNothing);
      expect(find.byKey(const Key('documents_category_error')), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Réessayer'));

      verify(() => mockBloc.add(
            const DocumentsFilterChanged(DocumentCategory.photo),
          )).called(1);
    });
  });
}
