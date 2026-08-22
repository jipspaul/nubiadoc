import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/patient_account.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class SendAccessRequestUseCase {
  final AccountRepository _repository;
  const SendAccessRequestUseCase(this._repository);

  Future<Either<Failure, AccessRequest>> call({
    required String firstName,
    required String lastName,
    required DependentRelationship relationship,
    required AccessRequestChannel channel,
    required Set<AccessRight> scope,
    String? email,
    String? phone,
  }) =>
      _repository.sendAccessRequest(
        firstName: firstName,
        lastName: lastName,
        relationship: relationship,
        channel: channel,
        scope: scope,
        email: email,
        phone: phone,
      );
}
