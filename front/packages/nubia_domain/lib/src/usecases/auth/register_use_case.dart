import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class RegisterUseCase {
  final AuthRepository _repository;
  const RegisterUseCase(this._repository);

  Future<Either<Failure, PatientAccount>> call({
    required String email,
    required String password,
    required String inviteToken,
  }) {
    if (inviteToken.isEmpty) {
      return Future.value(
        const Left(ValidationFailure(message: "Jeton d'invitation manquant.")),
      );
    }
    return _repository.register(
      email: email,
      password: password,
      inviteToken: inviteToken,
    );
  }
}
