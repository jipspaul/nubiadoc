import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';

abstract class SecretariatRepository {
  Future<Either<Failure, List<Secretariat>>> list();
  Future<Either<Failure, Secretariat>> getById(String id);
  Future<Either<Failure, Secretariat>> create(Secretariat secretariat);
  Future<Either<Failure, Secretariat>> update(Secretariat secretariat);
}
