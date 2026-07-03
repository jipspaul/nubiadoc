import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class AddDependentUseCase {
  final AccountRepository _repository;
  const AddDependentUseCase(this._repository);

  Future<Either<Failure, Dependent>> call({
    required String firstName,
    required String lastName,
    DateTime? birthDate,
    required DependentRelationship relationship,
  }) =>
      _repository.addDependent(
        firstName: firstName,
        lastName: lastName,
        birthDate: birthDate,
        relationship: relationship,
      );
}
