import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_data/src/remote/documents/document_api.dart';
import 'package:nubia_data/src/remote/documents/document_dto.dart';
import 'package:nubia_data/src/repositories/document_repository_impl.dart';
import 'package:nubia_domain/src/entities/document.dart';

class MockDocumentApi extends Mock implements DocumentApi {}

void main() {
  // #8375 : « Consigne 24 » et « Autre 26 » comptent plusieurs catégories
  // API (categoryCounts additionne) mais le filtre n'en interrogeait qu'une
  // (getByCategory) — getByCategory doit interroger exactement les mêmes
  // codes API que categoryCounts additionne pour cette catégorie.
  group('DocumentRepositoryImpl.getByCategory', () {
    late MockDocumentApi api;
    late DocumentRepositoryImpl repository;

    setUp(() {
      api = MockDocumentApi();
      repository = DocumentRepositoryImpl(api);
    });

    DocumentDto dto(String id, String category, String createdAt) =>
        DocumentDto(
          id: id,
          category: category,
          filename: '$id.pdf',
          mimeType: 'application/pdf',
          fileSizeBytes: 100,
          createdAt: createdAt,
        );

    test(
        'instructions interroge consigne ET attestation, puis fusionne/trie '
        'par date', () async {
      when(() => api.getByCategory('consigne')).thenAnswer(
        (_) async => [dto('c1', 'consigne', '2026-09-18T09:00:00Z')],
      );
      when(() => api.getByCategory('attestation')).thenAnswer(
        (_) async => [dto('a1', 'attestation', '2026-09-30T09:00:00Z')],
      );

      final result =
          await repository.getByCategory(DocumentCategory.instructions);

      final docs = result.fold((_) => <Document>[], (docs) => docs);
      expect(docs.map((d) => d.id), ['a1', 'c1']);
      verify(() => api.getByCategory('consigne')).called(1);
      verify(() => api.getByCategory('attestation')).called(1);
    });

    test(
        'other interroge les catégories API sans correspondance '
        '(courrier, dmsm, passeport_implantaire) — jamais "other"', () async {
      when(() => api.getByCategory('courrier')).thenAnswer(
        (_) async => [dto('co1', 'courrier', '2026-09-01T09:00:00Z')],
      );
      when(() => api.getByCategory('dmsm')).thenAnswer(
        (_) async => [dto('d1', 'dmsm', '2026-09-02T09:00:00Z')],
      );
      when(() => api.getByCategory('passeport_implantaire'))
          .thenAnswer((_) async => []);

      final result = await repository.getByCategory(DocumentCategory.other);

      final docs = result.fold((_) => <Document>[], (docs) => docs);
      expect(docs.map((d) => d.id), ['d1', 'co1']);
      verifyNever(() => api.getByCategory('other'));
    });
  });
}
