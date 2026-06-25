import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../remote/today_notes/today_notes_api.dart';

class TodayNotesRepositoryImpl implements TodayNotesRepository {
  final TodayNotesApi _api;

  const TodayNotesRepositoryImpl(this._api);

  @override
  Future<Either<Failure, List<ClinicalNoteSummary>>> getTodayNotes() async {
    try {
      final raw = await _api.getTodayNotes();
      final notes = raw.map((e) {
        return ClinicalNoteSummary(
          id: (e['id'] as String?) ?? '',
          timestamp: DateTime.tryParse(
                (e['timestamp'] ?? e['started_at'] ?? '') as String,
              ) ??
              DateTime.now(),
          patientInitials: (e['patient_initials'] as String?) ?? '',
          status: (e['status'] as String?) ?? '',
        );
      }).toList();
      return Right(notes);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return const Left(UnauthorizedFailure());
      }
      if (e.response?.statusCode == 404) {
        return const Right([]);
      }
      return const Right([]);
    } catch (_) {
      return const Right([]);
    }
  }
}
