import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';
import 'package:nubia_patient/domain/repositories/auth_repository.dart';

@injectable
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
