import 'dart:typed_data';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_design_system/nubia_design_system.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/documents/documents_bloc.dart';
import 'package:app_patient/features/documents/documents_event.dart';
import 'package:app_patient/features/documents/documents_page.dart';
import 'package:app_patient/features/documents/documents_state.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockGetDocumentsUseCase extends Mock implements GetDocumentsUseCase {}

class MockGetDocumentSignedUrlUseCase extends Mock
    implements GetDocumentSignedUrlUseCase {}

class MockUploadDocumentUseCase extends Mock implements UploadDocumentUseCase {}

class MockDocumentsBloc extends MockBloc<DocumentsEvent, DocumentsState>
    implements DocumentsBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _doc = Document(
  id: 'doc-1',
  name: 'Devis cabinet Lyon.pdf',
  category: DocumentCategory.quote,
  createdAt: DateTime(2026, 1, 15),
  fileSizeBytes: 102400,
  mimeType: 'application/pdf',
);

DocumentsBloc _makeBloc({
  required MockGetDocumentsUseCase getDocuments,
  required MockGetDocumentSignedUrlUseCase getSignedUrl,
  required MockUploadDocumentUseCase upload,
}) =>
    DocumentsBloc(
      getDocuments: getDocuments,
      getSignedUrl: getSignedUrl,
      upload: upload,
    );

/// Inline body widget that consumes the BlocProvider from the test without
/// creating its own (DocumentsPage creates one via GetIt).
class _DocumentsBodyDirect extends StatelessWidget {
  const _DocumentsBodyDirect();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentsBloc, DocumentsState>(
      builder: (context, state) {
        if (state is DocumentsLoading || state is DocumentsInitial) {
          return const Center(
            key: Key('documents_loading'),
            child: CircularProgressIndicator(),
          );
        }
        if (state is DocumentsError) {
          return Center(
            key: const Key('documents_error'),
            child: Text(state.message),
          );
        }
        if (state is DocumentsLoaded) {
          final docs = state.filtered;
          if (docs.isEmpty) {
            return const Center(
              key: Key('documents_empty'),
              child: Text('Aucun document'),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => context
                .read<DocumentsBloc>()
                .add(const DocumentsLoadRequested()),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final d in docs)
                  Text(key: Key('document_${d.id}'), d.name),
              ],
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}

Widget _wrap(DocumentsBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: _DocumentsBodyDirect()),
      ),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(DocumentCategory.other);
    registerFallbackValue(const DocumentsLoadRequested());
    registerFallbackValue(const DocumentsFilterChanged(null));
  });

  late MockGetDocumentsUseCase mockGetDocuments;
  late MockGetDocumentSignedUrlUseCase mockGetSignedUrl;
  late MockUploadDocumentUseCase mockUpload;

  setUp(() {
    mockGetDocuments = MockGetDocumentsUseCase();
    mockGetSignedUrl = MockGetDocumentSignedUrlUseCase();
    mockUpload = MockUploadDocumentUseCase();
  });

  group('DocumentsPage widget', () {
    testWidgets('affiche le spinner en état chargement', (tester) async {
      final bloc = _makeBloc(
        getDocuments: mockGetDocuments,
        getSignedUrl: mockGetSignedUrl,
        upload: mockUpload,
      );

      await tester.pumpWidget(_wrap(bloc));

      expect(find.byKey(const Key('documents_loading')), findsOneWidget);
    });

    testWidgets('affiche "Aucun document" quand la liste est vide',
        (tester) async {
      when(() => mockGetDocuments()).thenAnswer(
        (_) async => const Right([]),
      );

      final bloc = _makeBloc(
        getDocuments: mockGetDocuments,
        getSignedUrl: mockGetSignedUrl,
        upload: mockUpload,
      )..add(const DocumentsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_empty')), findsOneWidget);
    });

    testWidgets('affiche le nom du document quand la liste est chargée',
        (tester) async {
      when(() => mockGetDocuments()).thenAnswer(
        (_) async => Right([_doc]),
      );

      final bloc = _makeBloc(
        getDocuments: mockGetDocuments,
        getSignedUrl: mockGetSignedUrl,
        upload: mockUpload,
      )..add(const DocumentsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document_doc-1')), findsOneWidget);
      expect(find.text('Devis cabinet Lyon.pdf'), findsOneWidget);
    });

    testWidgets("affiche le message d'erreur en état erreur", (tester) async {
      when(() => mockGetDocuments()).thenAnswer(
        (_) async => const Left(NetworkFailure('Erreur réseau.')),
      );

      final bloc = _makeBloc(
        getDocuments: mockGetDocuments,
        getSignedUrl: mockGetSignedUrl,
        upload: mockUpload,
      )..add(const DocumentsLoadRequested());

      await tester.pumpWidget(_wrap(bloc));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents_error')), findsOneWidget);
      expect(find.text('Erreur réseau.'), findsOneWidget);
    });

    testWidgets('pull-to-refresh dispatch DocumentsLoadRequested',
        (tester) async {
      final mockBloc = MockDocumentsBloc();
      whenListen(
        mockBloc,
        Stream<DocumentsState>.empty(),
        initialState: DocumentsLoaded([_doc]),
      );

      await tester.pumpWidget(_wrap(mockBloc));
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, 400));
      await tester.pumpAndSettle();

      verify(
        () => mockBloc.add(any(that: isA<DocumentsLoadRequested>())),
      ).called(1);
    });
  });

  group('DocumentsPage — filtre catégorie', () {
    final docs = [
      Document(
        id: 'p1',
        name: 'Ordonnance Dupont.pdf',
        category: DocumentCategory.prescription,
        createdAt: DateTime(2026, 1, 1),
        fileSizeBytes: 1024,
        mimeType: 'application/pdf',
      ),
      Document(
        id: 'r1',
        name: 'Compte rendu opération.pdf',
        category: DocumentCategory.report,
        createdAt: DateTime(2026, 1, 2),
        fileSizeBytes: 2048,
        mimeType: 'application/pdf',
      ),
      Document(
        id: 'i1',
        name: 'Radio panoramique.pdf',
        category: DocumentCategory.xray,
        createdAt: DateTime(2026, 1, 3),
        fileSizeBytes: 4096,
        mimeType: 'application/pdf',
      ),
    ];

    setUp(() async {
      when(() => mockGetDocuments()).thenAnswer((_) async => Right(docs));
      await GetIt.instance.reset();
      GetIt.instance.registerFactory<DocumentsBloc>(() => DocumentsBloc(
            getDocuments: mockGetDocuments,
            getSignedUrl: mockGetSignedUrl,
            upload: mockUpload,
          ));
    });

    tearDown(() async => GetIt.instance.reset());

    testWidgets(
        'tap chip Ordonnances — 1 doc visible sur 3 de catégories différentes',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 4 chips visibles (Tous + 3 catégories réellement présentes)
      expect(find.byType(ChoiceChip), findsNWidgets(4));

      // 3 docs visibles avant filtrage
      expect(find.byKey(const Key('document_p1')), findsOneWidget);
      expect(find.byKey(const Key('document_r1')), findsOneWidget);
      expect(find.byKey(const Key('document_i1')), findsOneWidget);

      // Tap chip 'Ordonnance' (filtre catégorie prescription)
      await tester.tap(find.byKey(const Key('filter_prescription')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('document_p1')), findsOneWidget);
      expect(find.byKey(const Key('document_r1')), findsNothing);
      expect(find.byKey(const Key('document_i1')), findsNothing);
    });
  });

  group('DocumentsPage — taille fichier (#3349)', () {
    setUp(() async {
      await GetIt.instance.reset();
      GetIt.instance.registerFactory<DocumentsBloc>(() => DocumentsBloc(
            getDocuments: mockGetDocuments,
            getSignedUrl: mockGetSignedUrl,
            upload: mockUpload,
          ));
    });

    tearDown(() async => GetIt.instance.reset());

    testWidgets('affiche la taille formatée (Ko) quand size_bytes est présent',
        (tester) async {
      when(() => mockGetDocuments()).thenAnswer((_) async => Right([
            Document(
              id: 'd1',
              name: 'Devis.pdf',
              category: DocumentCategory.quote,
              createdAt: DateTime(2026, 1, 1),
              fileSizeBytes: 102400, // 100 Ko
              mimeType: 'application/pdf',
            ),
          ]));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('100 Ko'), findsOneWidget);
    });

    testWidgets('masque la taille (pas de « 0 Ko ») quand size_bytes vaut 0',
        (tester) async {
      when(() => mockGetDocuments()).thenAnswer((_) async => Right([
            Document(
              id: 'd2',
              name: 'Ordonnance.pdf',
              category: DocumentCategory.prescription,
              createdAt: DateTime(2026, 1, 1),
              fileSizeBytes: 0,
              mimeType: 'application/pdf',
            ),
          ]));

      await tester.pumpWidget(
        MaterialApp(
          theme: NubiaTheme.light,
          home: const Scaffold(body: DocumentsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('0 Ko'), findsNothing);
      // Le titre porte la date ; sans taille ni émetteur, la méta retombe
      // sur le seul libellé de catégorie.
      expect(find.textContaining('Ordonnance du 1 janv.'), findsOneWidget);
    });
  });

  group('DocumentsBloc', () {
    blocTest<DocumentsBloc, DocumentsState>(
      'émet [Loading, Loaded(vide)] quand la liste est vide',
      build: () {
        when(() => mockGetDocuments()).thenAnswer(
          (_) async => const Right([]),
        );
        return _makeBloc(
          getDocuments: mockGetDocuments,
          getSignedUrl: mockGetSignedUrl,
          upload: mockUpload,
        );
      },
      act: (bloc) => bloc.add(const DocumentsLoadRequested()),
      expect: () => [
        const DocumentsLoading(),
        isA<DocumentsLoaded>().having((s) => s.documents, 'documents', isEmpty),
      ],
    );

    blocTest<DocumentsBloc, DocumentsState>(
      'émet [Loading, Error] quand la liste échoue',
      build: () {
        when(() => mockGetDocuments()).thenAnswer(
          (_) async => const Left(NetworkFailure('Erreur réseau.')),
        );
        return _makeBloc(
          getDocuments: mockGetDocuments,
          getSignedUrl: mockGetSignedUrl,
          upload: mockUpload,
        );
      },
      act: (bloc) => bloc.add(const DocumentsLoadRequested()),
      expect: () => [
        const DocumentsLoading(),
        isA<DocumentsError>()
            .having((s) => s.message, 'message', 'Erreur réseau.'),
      ],
    );

    blocTest<DocumentsBloc, DocumentsState>(
      'émet [Loaded, DownloadReady] quand le téléchargement réussit',
      build: () {
        when(() => mockGetSignedUrl(any())).thenAnswer(
          (_) async => const Right('https://storage.example.com/signed'),
        );
        return _makeBloc(
          getDocuments: mockGetDocuments,
          getSignedUrl: mockGetSignedUrl,
          upload: mockUpload,
        );
      },
      seed: () => DocumentsLoaded([_doc]),
      act: (bloc) => bloc.add(const DocumentsDownloadRequested('doc-1')),
      expect: () => [
        isA<DocumentsDownloadReady>()
            .having((s) => s.documentId, 'documentId', 'doc-1')
            .having(
              (s) => s.url,
              'url',
              'https://storage.example.com/signed',
            ),
      ],
    );

    blocTest<DocumentsBloc, DocumentsState>(
      'émet [Loaded+pendingUpload, Loaded avec le document inséré] '
      "lors d'un upload réussi",
      build: () {
        when(() => mockUpload(
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
              mimeType: any(named: 'mimeType'),
              category: any(named: 'category'),
            )).thenAnswer((_) async => Right(_doc));
        return _makeBloc(
          getDocuments: mockGetDocuments,
          getSignedUrl: mockGetSignedUrl,
          upload: mockUpload,
        );
      },
      act: (bloc) => bloc.add(DocumentsUploadRequested(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'test.pdf',
        mimeType: 'application/pdf',
        category: DocumentCategory.quote,
      )),
      expect: () => [
        isA<DocumentsLoaded>()
            .having((s) => s.documents, 'documents', isEmpty)
            .having(
              (s) => s.pendingUpload?.filename,
              'pendingUpload.filename',
              'test.pdf',
            ),
        isA<DocumentsLoaded>()
            .having((s) => s.pendingUpload, 'pendingUpload', isNull)
            .having(
              (s) => s.documents.map((d) => d.id),
              'documents',
              ['doc-1'],
            ),
      ],
    );

    blocTest<DocumentsBloc, DocumentsState>(
      'émet [Loaded+pendingUpload, Loaded+pendingUpload en échec] '
      "lors d'un upload en échec",
      build: () {
        when(() => mockUpload(
              bytes: any(named: 'bytes'),
              filename: any(named: 'filename'),
              mimeType: any(named: 'mimeType'),
              category: any(named: 'category'),
            )).thenAnswer(
          (_) async => const Left(NetworkFailure('Upload impossible.')),
        );
        return _makeBloc(
          getDocuments: mockGetDocuments,
          getSignedUrl: mockGetSignedUrl,
          upload: mockUpload,
        );
      },
      act: (bloc) => bloc.add(DocumentsUploadRequested(
        bytes: Uint8List.fromList([1, 2, 3]),
        filename: 'test.pdf',
        mimeType: 'application/pdf',
        category: DocumentCategory.quote,
      )),
      expect: () => [
        isA<DocumentsLoaded>().having(
          (s) => s.pendingUpload?.failed,
          'pendingUpload.failed',
          false,
        ),
        isA<DocumentsLoaded>()
            .having((s) => s.pendingUpload?.failed, 'pendingUpload.failed', true)
            .having(
              (s) => s.pendingUpload?.errorMessage,
              'pendingUpload.errorMessage',
              'Upload impossible.',
            ),
      ],
    );
  });
}
