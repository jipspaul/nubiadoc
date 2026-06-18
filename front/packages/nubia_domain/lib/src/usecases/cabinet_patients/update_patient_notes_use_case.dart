import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

class UpdatePatientNotesUseCase {
  final CabinetPatientsRepository _repository;

  const UpdatePatientNotesUseCase(this._repository);

  Future<Either<Failure, CabinetPatient>> call(String id, String note) =>
      _repository.updateNotes(id, note);
}
