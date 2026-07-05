import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:nubia_domain/nubia_domain.dart';

import '../remote/today_notes/today_notes_api.dart';

class TodayNotesRepositoryImpl implements TodayNotesRepository {
  final TodayNotesApi _api;

  const TodayNotesRepositoryImpl(this._api);

  /// GET /v1/cabinet/today-notes (#3368). Un 404 (API déployée en retard)
  /// retombe silencieusement sur l'état vide — pas de bannière d'erreur pour
  /// une carte de survol.
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
      return const Right([]);
    } catch (_) {
      return const Right([]);
    }
  }
}
