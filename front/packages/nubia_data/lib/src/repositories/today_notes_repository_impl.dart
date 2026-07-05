import 'package:dartz/dartz.dart';
import 'package:nubia_domain/nubia_domain.dart';

class TodayNotesRepositoryImpl implements TodayNotesRepository {
  const TodayNotesRepositoryImpl();

  /// GET /v1/cabinet/today-notes n'est pas encore déployé côté API (404 sur
  /// chaque appel, cf. #3383). En attendant, on ne tente plus l'appel — la
  /// carte "Notes du jour" retombe directement sur son état vide plutôt que
  /// de générer un console.error réseau à chaque chargement du dashboard.
  @override
  Future<Either<Failure, List<ClinicalNoteSummary>>> getTodayNotes() async {
    return const Right([]);
  }
}
