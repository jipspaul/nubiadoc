import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:app_patient/features/oubliettes/oubliettes_bloc.dart';

class _MockGetDocuments extends Mock implements GetDocumentsUseCase {}

Document _doc(String id, String name, DateTime at) => Document(
      id: id,
      name: name,
      category: DocumentCategory.other,
      createdAt: at,
      fileSizeBytes: 1024,
      mimeType: 'application/pdf',
    );

void main() {
  late _MockGetDocuments getDocuments;

  setUp(() => getDocuments = _MockGetDocuments());

  OubliettesBloc build() => OubliettesBloc(getDocuments: getDocuments);

  blocTest<OubliettesBloc, OubliettesState>(
    'charge les documents récents et les mappe en OublietteItem',
    build: () {
      when(() => getDocuments(category: any(named: 'category'))).thenAnswer(
        (_) async => Right([
          _doc('a', 'Ordonnance Dr Martin', DateTime(2026, 6, 19)),
          _doc('b', 'Radio panoramique', DateTime(2026, 6, 18)),
        ]),
      );
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [
      const OubliettesLoading(),
      OubliettesLoaded([
        OublietteItem(
            id: 'a',
            title: 'Ordonnance Dr Martin',
            seenAt: DateTime(2026, 6, 19)),
        OublietteItem(
            id: 'b', title: 'Radio panoramique', seenAt: DateTime(2026, 6, 18)),
      ]),
    ],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'liste vide → OubliettesEmpty',
    build: () {
      when(() => getDocuments(category: any(named: 'category')))
          .thenAnswer((_) async => const Right([]));
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [const OubliettesLoading(), const OubliettesEmpty()],
  );

  blocTest<OubliettesBloc, OubliettesState>(
    'échec usecase → OubliettesError',
    build: () {
      when(() => getDocuments(category: any(named: 'category'))).thenAnswer(
          (_) async =>
              const Left(ServerFailure(message: 'boom', statusCode: 500)));
      return build();
    },
    act: (b) => b.add(const OubliettesLoadRequested()),
    expect: () => [const OubliettesLoading(), const OubliettesError('boom')],
  );
}
