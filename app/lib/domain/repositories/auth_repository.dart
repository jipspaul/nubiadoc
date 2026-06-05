import 'package:dartz/dartz.dart';
import 'package:nubia_patient/core/error/failure.dart';
import 'package:nubia_patient/domain/entities/patient_account.dart';

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
  Future<Either<Failure, PatientAccount>> getMe();
  Future<Either<Failure, void>> logout();
  Future<Either<Failure, void>> refreshToken();
  Future<bool> isAuthenticated();
}
