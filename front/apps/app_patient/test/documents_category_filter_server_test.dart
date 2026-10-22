// Issue #8363 — régression de #8297/#8318 : les puces de catégorie annoncent
// désormais le compte SERVEUR (#8333), mais le filtrage restait client, sur
// la seule page déjà chargée en mémoire (20 documents). Une catégorie
// absente de cette page (ex. CBCT, 3 documents plus loin dans le coffre)
// s'affichait donc comme vide alors que sa puce annonçait un compte non
// nul. Même règle que #8319 (recherche) : un document existant ne doit
// jamais être annoncé absent au seul motif qu'il n'a pas encore été
// paginé — ici, le filtre doit interroger le coffre-fort entier côté
// serveur plutôt que la page chargée.
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
  group('filtre catégorie interroge le coffre-fort entier (bloc réel)', () {
    late _MockGetDocuments mockGetDocuments;
    late _MockGetSignedUrl mockGetSignedUrl;
    late _MockUpload mockUpload;

    // Les 20 documents de la première page (#8297) : aucun CBCT, comme
    // dans la repro #8363. Les 3 CBCT existent bien sur le coffre-fort
    // entier, remontés par la facette serveur (#8318) mais absents de
    // cette page.
    final firstPage = List.generate(
      20,
      (i) => Document(
        id: 'doc-$i',
        name: 'Ordonnance $i.pdf',
        category: DocumentCategory.prescription,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024,
        mimeType: 'application/pdf',
      ),
    );

    final cbctDocs = [
      Document(
        id: 'cbct-1',
        name: 'CBCT 1.pdf',
        category: DocumentCategory.cbct,
        createdAt: DateTime(2026, 2, 1),
        fileSizeBytes: 8192,
        mimeType: 'application/pdf',
      ),
      Document(
        id: 'cbct-2',
        name: 'CBCT 2.pdf',
        category: DocumentCategory.cbct,
        createdAt: DateTime(2026, 2, 2),
        fileSizeBytes: 8192,
        mimeType: 'application/pdf',
      ),
      Document(
        id: 'cbct-3',
        name: 'CBCT 3.pdf',
        category: DocumentCategory.cbct,
        createdAt: DateTime(2026, 2, 3),
        fileSizeBytes: 8192,
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
            Right((documents: firstPage, nextCursor: null, total: 758)),
      );
      when(() => mockGetDocuments.categoryCounts(
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer(
        (_) async => const Right({
          DocumentCategory.prescription: 449,
          DocumentCategory.cbct: 3,
        }),
      );
      when(() => mockGetDocuments.call(
            category: DocumentCategory.cbct,
            patientAccount: any(named: 'patientAccount'),
          )).thenAnswer((_) async => Right(cbctDocs));

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
        'tap puce CBCT (absente de la page chargée) — requête serveur puis '
        'les 3 CBCT apparaissent, jamais "aucun document" (#8363)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CBCT 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('filter_cbct')));
      await tester.pumpAndSettle();

      // La requête serveur dédiée a bien été émise — pas de filtrage
      // purement client sur la page déjà chargée.
      verify(() => mockGetDocuments.call(
            category: DocumentCategory.cbct,
            patientAccount: any(named: 'patientAccount'),
          )).called(1);

      expect(find.byKey(const Key('documents_no_results')), findsNothing);
      expect(find.byKey(const Key('document_cbct-1')), findsOneWidget);
      expect(find.byKey(const Key('document_cbct-2')), findsOneWidget);
      expect(find.byKey(const Key('document_cbct-3')), findsOneWidget);
    });
  });

  group('squelette pendant la requête serveur (bloc simulé)', () {
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
        'requête serveur en cours pour la catégorie — squelette affiché, '
        'pas "Aucun document dans cette catégorie" (#8363)', (tester) async {
      whenListen(
        mockBloc,
        const Stream<DocumentsState>.empty(),
        initialState: const DocumentsLoaded(
          [],
          activeFilter: DocumentCategory.cbct,
          total: 758,
          isLoadingCategory: true,
          categoryCounts: {DocumentCategory.cbct: 3},
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
      expect(find.byKey(const Key('documents_loading')), findsOneWidget);
    });
  });
}
