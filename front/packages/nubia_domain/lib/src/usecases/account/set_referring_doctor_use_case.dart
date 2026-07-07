import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/referring_doctor.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/account_repository.dart';

class SetReferringDoctorUseCase {
  final AccountRepository _repository;

  const SetReferringDoctorUseCase(this._repository);

  Future<Either<Failure, ReferringDoctor>> call({
    String? providerId,
    required String name,
    String? specialty,
    String? phone,
    String? email,
    String? address,
  }) =>
      _repository.setReferringDoctor(
        providerId: providerId,
        name: name,
        specialty: specialty,
        phone: phone,
        email: email,
        address: address,
      );
}
