import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class UpdateAccountUseCase {
  final AccountRepository _repository;

  const UpdateAccountUseCase(this._repository);

  /// Champs absents : non modifiés côté back (PATCH partiel, COALESCE) — cf.
  /// [AccountRepository.updateAccount]. #4544 : ces params étaient `required`
  /// ici alors que le repository/back les traitent déjà en optionnel, ce qui
  /// forçait tout appelant (ex. modifier juste le téléphone) à réenvoyer des
  /// valeurs déjà connues, ou à en fabriquer quand elles manquaient
  /// (`dateOfBirth` nullable côté [PatientAccount]).
  Future<Either<Failure, PatientAccount>> call({
    String? firstName,
    String? lastName,
    String? phone,
    DateTime? dateOfBirth,
  }) {
    return _repository.updateAccount(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      dateOfBirth: dateOfBirth,
    );
  }
}
