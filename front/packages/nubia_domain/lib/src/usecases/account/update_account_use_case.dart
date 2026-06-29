import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class UpdateAccountUseCase {
  final AccountRepository _repository;

  const UpdateAccountUseCase(this._repository);

  Future<Either<Failure, PatientAccount>> call({
    required String firstName,
    required String lastName,
    required String phone,
    required DateTime dateOfBirth,
  }) {
    return _repository.updateAccount(
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      dateOfBirth: dateOfBirth,
    );
  }
}
