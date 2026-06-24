import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/clinical_note_summary.dart';
import 'package:nubia_domain/src/error/failure.dart';

abstract class TodayNotesRepository {
  Future<Either<Failure, List<ClinicalNoteSummary>>> getTodayNotes();
}
