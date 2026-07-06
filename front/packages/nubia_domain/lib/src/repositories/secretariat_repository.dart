import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/secretariat.dart';

abstract class SecretariatRepository {
  Future<Either<Failure, List<Secretariat>>> list();
  Future<Either<Failure, Secretariat>> getById(String id);
  Future<Either<Failure, Secretariat>> create(Secretariat secretariat);
  Future<Either<Failure, Secretariat>> update(Secretariat secretariat);

  /// Crée le secrétariat puis provisionne le premier membre par email
  /// (POST /secretariats puis POST /secretariats/:id/staff).
  Future<Either<Failure, Secretariat>> invite({
    required String name,
    required String email,
  });
}
