import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class ResetPasswordUseCase {
  final AuthRepository _repository;
  const ResetPasswordUseCase(this._repository);

  Future<Either<Failure, void>> call({
    required String token,
    required String newPassword,
  }) {
    if (newPassword.length < 8 || !RegExp(r'[0-9]').hasMatch(newPassword)) {
      return Future.value(
        const Left(ValidationFailure(
          message:
              'Le mot de passe doit contenir au moins 8 caractères dont 1 chiffre.',
        )),
      );
    }
    return _repository.resetPassword(token: token, newPassword: newPassword);
  }
}
