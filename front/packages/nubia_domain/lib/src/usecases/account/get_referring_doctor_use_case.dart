import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/referring_doctor.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class GetReferringDoctorUseCase {
  final AccountRepository _repository;

  const GetReferringDoctorUseCase(this._repository);

  Future<Either<Failure, ReferringDoctor?>> call() =>
      _repository.getReferringDoctor();
}
