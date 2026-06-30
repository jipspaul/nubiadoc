import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';

/// PORT — auth boundary.
abstract class AuthRepository {
  Future<Either<Failure, PatientAccount>> login({
    required String email,
    required String password,
  });
  Future<Either<Failure, PatientAccount>> register({
    required String email,
    required String password,
    required String inviteToken,
  });
  Future<Either<Failure, String>> registerPro({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    String? rpps,
    String? adeli,
    required String raisonSociale,
    String? siret,
    required String specialite,
  });
  Future<Either<Failure, PatientAccount>> getMe();
  Future<Either<Failure, void>> logout();
  Future<Either<Failure, void>> refreshToken();
  Future<bool> isAuthenticated();
}
