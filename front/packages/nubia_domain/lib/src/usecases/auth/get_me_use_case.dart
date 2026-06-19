import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/auth_repository.dart';

class GetMeUseCase {
  final AuthRepository _repository;
  const GetMeUseCase(this._repository);

  Future<Either<Failure, PatientAccount>> call() => _repository.getMe();
}
