import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:nubia_domain/nubia_domain.dart';

import 'package:nubia_data/src/remote/today_notes/today_notes_api.dart';
import 'package:nubia_data/src/repositories/today_notes_repository_impl.dart';

class MockTodayNotesApi extends Mock implements TodayNotesApi {}

Map<String, dynamic> _rawNote(String id, String status) => {
      'id': id,
      'started_at': '2026-06-22T09:00:00Z',
      'patient_initials': 'MD',
      'status': status,
    };

void main() {
  late MockTodayNotesApi api;
  late TodayNotesRepositoryImpl repo;

  setUp(() {
    api = MockTodayNotesApi();
    repo = TodayNotesRepositoryImpl(api);
  });

  group('getTodayNotes — mapping statut API → ClinicalNoteStatus (#5053)', () {
    test('« completed » → signed', () async {
      when(() => api.getTodayNotes())
          .thenAnswer((_) async => [_rawNote('n1', 'completed')]);

      final result = await repo.getTodayNotes();

      result.fold(
        (_) => fail('attendu Right'),
        (notes) => expect(notes.single.status, ClinicalNoteStatus.signed),
      );
    });

    test('« in_progress » → draft', () async {
      when(() => api.getTodayNotes())
          .thenAnswer((_) async => [_rawNote('n1', 'in_progress')]);

      final result = await repo.getTodayNotes();

      result.fold(
        (_) => fail('attendu Right'),
        (notes) => expect(notes.single.status, ClinicalNoteStatus.draft),
      );
    });

    test('« cancelled » (non signée) → unsigned, jamais signed', () async {
      when(() => api.getTodayNotes())
          .thenAnswer((_) async => [_rawNote('n1', 'cancelled')]);

      final result = await repo.getTodayNotes();

      result.fold(
        (_) => fail('attendu Right'),
        (notes) {
          expect(notes.single.status, ClinicalNoteStatus.unsigned);
          expect(notes.single.status, isNot(ClinicalNoteStatus.signed));
        },
      );
    });

    test('statut inconnu → unknown (défaut sûr)', () async {
      when(() => api.getTodayNotes())
          .thenAnswer((_) async => [_rawNote('n1', 'garbage')]);

      final result = await repo.getTodayNotes();

      result.fold(
        (_) => fail('attendu Right'),
        (notes) => expect(notes.single.status, ClinicalNoteStatus.unknown),
      );
    });

    test('401 → UnauthorizedFailure', () async {
      when(() => api.getTodayNotes()).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          response: Response(
            requestOptions: RequestOptions(path: '/x'),
            statusCode: 401,
          ),
        ),
      );

      final result = await repo.getTodayNotes();

      expect(result.isLeft(), isTrue);
    });
  });
}
