import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/oubliettes/oubliettes_bloc.dart';

class _MockGetDocuments extends Mock implements GetDocumentsUseCase {}

class _MockGetDocumentSignedUrl extends Mock
    implements GetDocumentSignedUrlUseCase {}

Document _doc(String id, String name, DateTime at,
        {DocumentCategory category = DocumentCategory.other}) =>
    Document(
      id: id,
      name: name,
      category: category,
      createdAt: at,
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    );

void main() {
  late _MockGetDocuments getDocuments;
  late _MockGetDocumentSignedUrl getDocumentSignedUrl;

  setUp(() {
    getDocuments = _MockGetDocuments();
    getDocumentSignedUrl = _MockGetDocumentSignedUrl();
  });

  OubliettesBloc build() => OubliettesBloc(
        getDocuments: getDocuments,
        getDocumentSignedUrl: getDocumentSignedUrl,
      );

  blocTest<OubliettesBloc, OubliettesState>(
    'charge les documents récents et les mappe en OublietteItem',
    build: () {
      when(() => getDocuments(
            category: any(named: 'category'), limit: any(named: 'limit'))).thenAnswer(
        (_) async => Right([
          _doc('a', 'ordonnance-f5e41471.pdf', DateTime(2026, 6, 19),
              category: DocumentCategory.prescription),
          _doc('b', 'radio-48c4a8df.pdf', DateTime(2026, 6, 18),
              category: DocumentCategory.xray),
        ]),
      );
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [
      const OubliettesLoading(),
      OubliettesLoaded([
        OublietteItem(
            id: 'a', title: 'Ordonnance du 19 juin', seenAt: DateTime(2026, 6, 19)),
        OublietteItem(
            id: 'b', title: 'Radio du 18 juin', seenAt: DateTime(2026, 6, 18)),
      ]),
    ],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'liste vide → OubliettesEmpty',
    build: () {
      when(() => getDocuments(
            category: any(named: 'category'), limit: any(named: 'limit')))
          .thenAnswer((_) async => const Right([]));
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [const OubliettesLoading(), const OubliettesEmpty()],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'échec usecase → OubliettesError',
    build: () {
      when(() => getDocuments(
            category: any(named: 'category'), limit: any(named: 'limit'))).thenAnswer(
          (_) async =>
              const Left(ServerFailure(message: 'boom', statusCode: 500)));
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [const OubliettesLoading(), const OubliettesError('boom')],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'OubliettesDocumentRequested → OubliettesDocumentReady avec l\'URL signée',
    build: () {
      when(() => getDocumentSignedUrl('a'))
          .thenAnswer((_) async => const Right('https://signed.url/a'));
      return build();
    },
    act: (b) => b.add(const OubliettesDocumentRequested('a')),
    expect: () => [const OubliettesDocumentReady('https://signed.url/a')],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'OubliettesDocumentRequested → OubliettesDocumentError si le usecase échoue',
    build: () {
      when(() => getDocumentSignedUrl('a')).thenAnswer(
          (_) async => const Left(ServerFailure(message: 'boom', statusCode: 500)));
      return build();
    },
    act: (b) => b.add(const OubliettesDocumentRequested('a')),
    expect: () => [const OubliettesDocumentError('boom')],
  );
}
