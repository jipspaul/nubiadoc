import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_bloc.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_event.dart';
import 'package:nubia_patient/presentation/features/documents/bloc/document_state.dart';

class MockDocumentRepository extends Mock implements DocumentRepository {}

final _documents = [
  Document(
    id: 'doc-1',
    name: 'Devis implant.pdf',
    category: DocumentCategory.quote,
    createdAt: DateTime(2026, 3, 10),
    fileSizeBytes: 204800,
    mimeType: 'application/pdf',
  ),
  Document(
    id: 'doc-2',
    name: 'Radio panoramique.jpg',
    category: DocumentCategory.xray,
    createdAt: DateTime(2026, 4, 5),
    fileSizeBytes: 1048576,
    mimeType: 'image/jpeg',
  ),
];

void main() {
  late MockDocumentRepository repository;

  setUpAll(() {
    registerFallbackValue(DocumentCategory.other);
    registerFallbackValue(const OfflineFailure());
  });

  setUp(() {
    repository = MockDocumentRepository();
  });

  group('DocumentBloc — chargement', () {
    blocTest<DocumentBloc, DocumentState>(
      'émet Loading puis Loaded quand le repo retourne des documents',
      build: () {
        when(() => repository.getAll())
            .thenAnswer((_) async => Right(_documents));
        return DocumentBloc(repository);
      },
      act: (bloc) => bloc.add(const DocumentLoadRequested()),
      expect: () => [
        const DocumentLoading(),
        DocumentLoaded(_documents),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'émet Loading puis Error quand le repo retourne une failure',
      build: () {
        when(() => repository.getAll())
            .thenAnswer((_) async => const Left(NetworkFailure()));
        return DocumentBloc(repository);
      },
      act: (bloc) => bloc.add(const DocumentLoadRequested()),
      expect: () => [
        const DocumentLoading(),
        const DocumentError('Erreur réseau. Vérifiez votre connexion.'),
      ],
    );
  });

  group('DocumentBloc — filtre par catégorie', () {
    blocTest<DocumentBloc, DocumentState>(
      'met à jour la catégorie sélectionnée sans recharger',
      build: () {
        when(() => repository.getAll())
            .thenAnswer((_) async => Right(_documents));
        return DocumentBloc(repository);
      },
      seed: () => DocumentLoaded(_documents),
      act: (bloc) =>
          bloc.add(const DocumentCategorySelected(DocumentCategory.quote)),
      expect: () => [
        DocumentLoaded(_documents,
            selectedCategory: DocumentCategory.quote),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'filtered ne contient que les documents de la catégorie',
      build: () {
        when(() => repository.getAll())
            .thenAnswer((_) async => Right(_documents));
        return DocumentBloc(repository);
      },
      seed: () => DocumentLoaded(_documents,
          selectedCategory: DocumentCategory.quote),
      act: (bloc) => bloc.add(const DocumentCategorySelected(null)),
      expect: () => [DocumentLoaded(_documents)],
      verify: (bloc) {
        final state = bloc.state as DocumentLoaded;
        expect(state.filtered.length, 2);
      },
    );
  });

  group('DocumentBloc — URL signée', () {
    blocTest<DocumentBloc, DocumentState>(
      'émet SignedUrlLoading puis SignedUrlReady quand le repo retourne une URL',
      build: () {
        when(() => repository.getSignedUrl('doc-1'))
            .thenAnswer((_) async =>
                const Right('https://storage.example.com/doc-1?sig=abc'));
        return DocumentBloc(repository);
      },
      seed: () => DocumentLoaded(_documents),
      act: (bloc) => bloc.add(const DocumentSignedUrlRequested('doc-1')),
      expect: () => [
        const DocumentSignedUrlLoading('doc-1'),
        const DocumentSignedUrlReady(
          documentId: 'doc-1',
          url: 'https://storage.example.com/doc-1?sig=abc',
        ),
      ],
    );

    blocTest<DocumentBloc, DocumentState>(
      'émet SignedUrlLoading puis SignedUrlError quand le repo retourne une failure',
      build: () {
        when(() => repository.getSignedUrl('doc-1')).thenAnswer(
            (_) async => const Left(ServerFailure(
                message: 'Erreur lors de la récupération du lien de téléchargement.')));
        return DocumentBloc(repository);
      },
      seed: () => DocumentLoaded(_documents),
      act: (bloc) => bloc.add(const DocumentSignedUrlRequested('doc-1')),
      expect: () => [
        const DocumentSignedUrlLoading('doc-1'),
        const DocumentSignedUrlError(
            'Erreur lors de la récupération du lien de téléchargement.'),
      ],
    );
  });
}
