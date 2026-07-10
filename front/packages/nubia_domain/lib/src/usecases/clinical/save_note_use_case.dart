import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/clinical_session_repository.dart';

class SaveNoteUseCase {
  final ClinicalSessionRepository _repository;

  const SaveNoteUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String consultationId,
    required String note,
  }) =>
      _repository.saveNote(consultationId: consultationId, note: note);
}
