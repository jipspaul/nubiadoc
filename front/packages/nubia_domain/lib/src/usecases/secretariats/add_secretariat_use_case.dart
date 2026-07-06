import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

class AddSecretariatUseCase {
  final SecretariatRepository _repository;

  const AddSecretariatUseCase(this._repository);

  Future<Either<Failure, Secretariat>> call({
    required String name,
    required String email,
  }) {
    if (name.trim().isEmpty) {
      return Future.value(
        const Left(ValidationFailure(message: 'Le nom est requis.')),
      );
    }
    if (email.isEmpty || !email.contains('@')) {
      return Future.value(
        const Left(ValidationFailure(message: 'Adresse e-mail invalide.')),
      );
    }
    return _repository.invite(name: name.trim(), email: email.trim());
  }
}
