import 'package:dartz/dartz.dart';
import 'package:nubia_domain/src/error/failure.dart';
import 'package:nubia_domain/src/repositories/compliance_repository.dart';

/// Clôture un item de l'échéancier de conformité (#7170) —
/// `POST /v1/cabinet/compliance-items/:id/complete`.
class CompleteComplianceItemUseCase {
  final ComplianceRepository _repository;

  const CompleteComplianceItemUseCase(this._repository);

  Future<Either<Failure, String>> call(String itemId) =>
      _repository.completeItem(itemId);
}
