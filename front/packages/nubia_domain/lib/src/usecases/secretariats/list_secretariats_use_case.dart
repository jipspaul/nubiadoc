import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';
import 'package:nubia_domain/src/repositories/secretariat_repository.dart';

class ListSecretiariatsUseCase {
  final SecretariatRepository _repository;

  const ListSecretiariatsUseCase(this._repository);

  Future<Either<Failure, List<Secretariat>>> call() => _repository.list();
}
