import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

class AddSecretariatUseCase {
  final SecretariatRepository _repository;

  const AddSecretariatUseCase(this._repository);

  Future<Either<Failure, Secretariat>> call(String email) =>
      _repository.invite(email);
}
