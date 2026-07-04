import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_session_repository.dart';

class GetPharmacyMembershipsUseCase {
  final PharmacySessionRepository _repository;
  const GetPharmacyMembershipsUseCase(this._repository);

  Future<Either<Failure, List<PharmacyMembership>>> call() =>
      _repository.myMemberships();
}
