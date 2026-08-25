import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

class ListSecretariatsUseCase {
  final SecretariatRepository _repository;

  const ListSecretariatsUseCase(this._repository);

  Future<Either<Failure, List<Secretariat>>> call() => _repository.list();
}
