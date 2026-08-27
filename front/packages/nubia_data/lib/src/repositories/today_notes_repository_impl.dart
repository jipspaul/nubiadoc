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
        final initials = (e['patient_initials'] as String?) ?? '';
        final name = e['patient_name'] as String?;
        return ClinicalNoteSummary(
          id: (e['id'] as String?) ?? '',
          timestamp: DateTime.tryParse(
                (e['timestamp'] ?? e['started_at'] ?? '') as String,
              ) ??
              DateTime.now(),
          patientInitials: initials,
          status: _parseStatus(e['status'] as String?),
          // #5047 : nom réel renvoyé par l'API (#6038), repli sur les
          // initiales si absent/vide par prudence.
          patientName: (name != null && name.trim().isNotEmpty)
              ? name
              : initials,
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

  /// Table de correspondance explicite statut API → [ClinicalNoteStatus]
  /// (#5053) — jamais de `String.contains` : « cancelled » (note non signée)
  /// ne doit jamais être confondu avec « completed » (note signée) par un
  /// matching approximatif. `cs.status` (`consultation_session`) ne connaît
  /// que `in_progress` / `completed` / `cancelled` (api/src/clinical.rs) ;
  /// toute autre valeur retombe sur [ClinicalNoteStatus.unknown].
  static ClinicalNoteStatus _parseStatus(String? value) {
    switch (value) {
      case 'completed':
        return ClinicalNoteStatus.signed;
      case 'in_progress':
        return ClinicalNoteStatus.draft;
      case 'cancelled':
        return ClinicalNoteStatus.unsigned;
      default:
        return ClinicalNoteStatus.unknown;
    }
  }
}
