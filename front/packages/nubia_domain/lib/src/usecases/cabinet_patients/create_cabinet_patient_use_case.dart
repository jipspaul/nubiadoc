import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/cabinet_patient.dart';
import 'package:nubia_domain/src/repositories/cabinet_patients_repository.dart';

/// Création rapide d'un dossier patient à l'accueil secrétariat (#4038).
class CreateCabinetPatientUseCase {
  final CabinetPatientsRepository _repository;

  const CreateCabinetPatientUseCase(this._repository);

  Future<Either<Failure, CabinetPatient>> call({
    required String firstName,
    required String lastName,
    String? phone,
    DateTime? birthDate,
  }) =>
      _repository.create(
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        birthDate: birthDate,
      );
}
