import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class LoginUseCase {
  final AuthRepository _repository;
  const LoginUseCase(this._repository);

  Future<Either<Failure, PatientAccount>> call({
    required String email,
    required String password,
  }) {
    if (email.isEmpty || !email.contains('@')) {
      return Future.value(
        const Left(ValidationFailure(message: 'Adresse e-mail invalide.')),
      );
    }
    if (password.isEmpty) {
      return Future.value(
        const Left(ValidationFailure(message: 'Le mot de passe est requis.')),
      );
    }
    return _repository.login(email: email, password: password);
  }
}
