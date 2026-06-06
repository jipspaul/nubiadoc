import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/document.dart';
import 'package:nubia_patient/domain/repositories/document_repository.dart';
import 'package:nubia_patient/domain/usecases/documents/get_document_signed_url_use_case.dart';
import 'package:nubia_patient/domain/usecases/documents/get_documents_use_case.dart';

class MockDocumentRepository extends Mock implements DocumentRepository {}

Document _makeDocument({
  String id = 'd1',
  DocumentCategory category = DocumentCategory.xray,
}) =>
    Document(
      id: id,
      name: 'radio.jpg',
      category: category,
      createdAt: DateTime(2026, 1, 1),
      fileSizeBytes: 204800,
      mimeType: 'image/jpeg',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(DocumentCategory.other);
  });

  late MockDocumentRepository repository;

  setUp(() {
    repository = MockDocumentRepository();
  });

  group('GetDocumentsUseCase', () {
    late GetDocumentsUseCase useCase;

    setUp(() => useCase = GetDocumentsUseCase(repository));

    test('returns all documents when no category filter', () async {
      final docs = [_makeDocument(id: 'd1'), _makeDocument(id: 'd2')];
      when(() => repository.getAll()).thenAnswer((_) async => Right(docs));

      final result = await useCase();

      expect(result, Right<Failure, List<Document>>(docs));
      verify(() => repository.getAll()).called(1);
      verifyNever(() => repository.getByCategory(any()));
    });

    test('delegates to getByCategory when category is provided', () async {
      final docs = [_makeDocument(category: DocumentCategory.xray)];
      when(() => repository.getByCategory(DocumentCategory.xray))
          .thenAnswer((_) async => Right(docs));

      final result = await useCase(category: DocumentCategory.xray);

      expect(result, Right<Failure, List<Document>>(docs));
      verify(() => repository.getByCategory(DocumentCategory.xray)).called(1);
      verifyNever(() => repository.getAll());
    });

    test('returns Failure on repository error', () async {
      when(() => repository.getAll()).thenAnswer(
        (_) async => const Left(ServerFailure(message: 'Erreur serveur.')),
      );

      final result = await useCase();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f, isA<ServerFailure>()),
        (_) => fail('expected failure'),
      );
    });
  });

  group('GetDocumentSignedUrlUseCase', () {
    late GetDocumentSignedUrlUseCase useCase;

    setUp(() => useCase = GetDocumentSignedUrlUseCase(repository));

    test('returns signed URL on success', () async {
      const url =
          'https://storage.example.com/docs/d1?sig=abc&expires=1234567890';
      when(() => repository.getSignedUrl('d1'))
          .thenAnswer((_) async => const Right(url));

      final result = await useCase('d1');

      expect(result, const Right<Failure, String>(url));
      verify(() => repository.getSignedUrl('d1')).called(1);
    });

    test('returns Failure on error', () async {
      when(() => repository.getSignedUrl(any()))
          .thenAnswer((_) async => const Left(NetworkFailure()));

      final result = await useCase('d1');

      expect(result.isLeft(), isTrue);
    });
  });
}
