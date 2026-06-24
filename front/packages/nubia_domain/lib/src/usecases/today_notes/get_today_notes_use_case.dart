import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/clinical_note_summary.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/today_notes_repository.dart';

class GetTodayNotesUseCase {
  final TodayNotesRepository _repository;

  const GetTodayNotesUseCase(this._repository);

  Future<Either<Failure, List<ClinicalNoteSummary>>> call() =>
      _repository.getTodayNotes();
}
