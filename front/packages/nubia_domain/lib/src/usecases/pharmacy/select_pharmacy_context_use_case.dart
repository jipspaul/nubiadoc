import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/entities/pharmacy_session.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/pharmacy_session_repository.dart';

class SelectPharmacyContextUseCase {
  final PharmacySessionRepository _repository;
  const SelectPharmacyContextUseCase(this._repository);

  Future<Either<Failure, PharmacyContext>> call(String pharmacyId) {
    if (pharmacyId.isEmpty) {
      return Future.value(
        const Left(ValidationFailure(message: 'Pharmacie requise.')),
      );
    }
    return _repository.selectContext(pharmacyId);
  }
}
