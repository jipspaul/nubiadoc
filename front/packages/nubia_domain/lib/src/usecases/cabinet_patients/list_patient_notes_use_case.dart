import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_note.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

class ListPatientNotesUseCase {
  final CabinetPatientsRepository _repository;

  const ListPatientNotesUseCase(this._repository);

  Future<Either<Failure, List<PatientNote>>> call(String id) =>
      _repository.listNotes(id);
}
